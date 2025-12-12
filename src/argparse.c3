// Copyright (c) 2025 Alex Veden <i@alexveden.com>. All rights reserved.
// Updated for current C3 v7.7 by Jack Li <li.jack.services@gmail.com> (syntax + faulting + any + macros)
// Last update: 12/10/2025 (mm/dd/yyyy)
//
//
module misc::argparse;

import std::io;
import std::io::path;

// Faults used by this module
faultdef
    ARGPARSE_MISSING_ARGUMENT,
    ARGPARSE_INVALID_ARGUMENT,
    ARGPARSE_ARGUMENT_VALUE,
    ARGPARSE_CONFIGURATION,
    ARGPARSE_HELP_SHOW;

// Internal enum for option kind
enum ArgType : int {
    USER,
    GROUP,
    HELP,
}

$assert(ArgType.USER.ordinal == 0);  // USER must be 0 to support ZII behaviour

// Parser behaviour flags
struct ArgParseFlags {
    /// Stops parsing on first non-option; remaining go to .arguments
    bool stop_at_non_option;
    /// Require at least one positional argument
    bool require_arguments;
}

// Internal parser context
struct ArgParseCtx {
    int      argc;
    String[] argv;
    String[] out;
    int      cpidx;
    String   optvalue;
    bool     has_argument;
}

// Callback type: ctx is just opt.value (any), value is raw string
alias ArgParseCallbackFn = fn void?(any ctx, String value);

// Option descriptor
struct ArgOpt {
    /// short option letter, default: '\0'
    char short_name;

    /// long option string, default: ""
    String long_name;

    /// option value or callback context, must always be non null (when used)
    any value;

    /// set true if value is mandatory (default: false)
    bool required;

    /// optional: help string for display
    String help;

    /// optional: custom parsing logic callback
    ArgParseCallbackFn callback;

    /// Allows passing multiple options of this type.
    /// If value type is `int` and no callback, acts as accumulator flag.
    bool allow_many;

    // Private fields

    /// Set to true if argument passed by the user
    bool _is_present;

    /// Private argument type
    ArgType _arg_type;
}

// Top-level parser object
struct ArgParse {
    /// Remaining positional arguments (after options)
    String[] arguments;
    /// Usage line; auto-generated if empty
    String usage;
    /// Description for --help
    String description;
    /// Footer for --help
    String epilog;
    /// Program name (defaults to argv[0])
    String program_name;
    /// All options
    ArgOpt[] options;

    /// Behaviour flags
    ArgParseFlags flags;

    /// Internal state
    ArgParseCtx _ctx;
}

// -----------------------------------------------------------------------------
// Convenience constructors (replacing old help_opt/group_opt macros)
// -----------------------------------------------------------------------------

/// Special template option for --help/-h - prints usage
fn ArgOpt help_opt(String help_prompt = "show this help message and exit")
{
    return (ArgOpt){
        ._arg_type  = ArgType.HELP,
        .short_name = 'h',
        .long_name  = "help",
        .help       = help_prompt,
        // value must be non-null, but we never actually use it
        .value      = any_make(null, bool.typeid),
    };
}

/// Section separator in usage printout
fn ArgOpt group_opt(String group_name)
{
    return (ArgOpt){
        ._arg_type = ArgType.GROUP,
        .help      = group_name,
    };
}

// -----------------------------------------------------------------------------
// Low-level iterator: ArgParse.next
// -----------------------------------------------------------------------------

/*
 Low-level argument parser, for fine-grained control.

 Returns each argv item in turn. For options like "--foo=bar",
 you get "--foo" first, and on the next call "bar".

 When used, you should not also call ArgParse.parse() on the same ArgParse.
*/
fn String? ArgParse.next(&self, String[] argv)
{
    assert(self.arguments.len == 0, "ArgParse already initialized or double parse call");

    if (!self._ctx.has_argument) {
        // initial call
        assert(argv.len > 0, "empty argv");
        self._ctx.argc  = argv.len - 1;
        self._ctx.cpidx = 0;
        self._ctx.argv  = argv[1..];
        self._ctx.out   = argv;
    }

    // protection flag (prevents mixed usage with ArgParse.parse())
    self._ctx.has_argument = true;

    if (self._ctx.argc > 0 && self._ctx.argv.len > 0) {
        String arg = self._ctx.argv[0];
        if (arg.len == 0) {
            io::printf("Error: argument too short `%s`\n", arg);
            return ARGPARSE_INVALID_ARGUMENT?;
        }

        if (self._ctx.cpidx > 0) {
            // we have --opt=foo, return 'foo' part
            arg = arg[self._ctx.cpidx + 1 ..];
            self._ctx.cpidx = 0;
        } else if (arg.starts_with("--")) {
            if (try idx = arg.index_of_char('=')) {
                // handling --opt=foo, returns '--opt' and 'foo'
                self._ctx.cpidx = (int)idx;

                if (idx == arg.len - 1) {
                    io::printf("Error: option has no value `%s`\n", arg);
                    return ARGPARSE_INVALID_ARGUMENT?;
                }
                arg = arg[..idx - 1];
                // return '--opt' part
                return arg;
            }
        }
        self._ctx.argc--;
        self._ctx.argv = self._ctx.argv[1..];
        return arg;
    }

    return "";
}

// -----------------------------------------------------------------------------
// High-level parse() API
// -----------------------------------------------------------------------------

/*
 Parse all arguments in one go.

 On success: returns void (no fault) and fills:
   - self.arguments   with remaining positionals
   - bound values via .value / .callback

 On failure: returns one of the ARGPARSE_* faults.
*/
fn void? ArgParse.parse(&self, String[] argv)
{
    assert(self.arguments.len == 0, "ArgParse already initialized or double parse call");
    assert(!self._ctx.has_argument, "ArgParse.next() already used before (pick only one way)?");
    assert(argv.len > 0);

    self._ctx.argc  = argv.len - 1;
    self._ctx.cpidx = 0;
    self._ctx.argv  = argv[1..];
    self._ctx.out   = argv;

    if (!self.program_name) {
        self.program_name = argv[0];
    }

    self.options_check()!;

    for (; self._ctx.argc && self._ctx.argv.len; self._ctx.argc--) {
        String arg = self._ctx.argv[0];

        if (arg.len == 0) {
            io::printf("Error: argument too short `%s`\n", arg);
            return ARGPARSE_INVALID_ARGUMENT?;
        }

        if (arg.len == 1 || arg[0] != '-' || arg[1] == '\0') {
            self._ctx.has_argument = true;

            if (self.flags.stop_at_non_option) {
                self._ctx.argc--;
                self._ctx.argv = self._ctx.argv[1..];
                break;
            } else {
                self._ctx.argv = self._ctx.argv[1..];
            }
            continue;
        }

        // short option
        if (arg[1] != '-') {
            self._ctx.optvalue = arg[1..];
            self._ctx.cpidx++;

            if (self._ctx.has_argument) {
                io::printf("Error: passing options after arguments not allowed at `%s`\n", arg);
                return ARGPARSE_INVALID_ARGUMENT?;
            }

            self.parse_short_arg()!;

            self._ctx.argv = self._ctx.argv[1..];

            // Parse stacked short args: '-f -a -b' as '-fab'
            while (self._ctx.optvalue) {
                self.parse_short_arg()!;
            }
            continue;
        }

        // if '--' present, stop option parsing
        if (arg.len == 2) {
            self._ctx.argc--;
            self._ctx.argv = self._ctx.argv[1..];
            self._ctx.cpidx++;
            break;
        }

        if (self._ctx.has_argument) {
            io::printf("Error: passing options after arguments not allowed at `%s`\n", arg);
            return ARGPARSE_INVALID_ARGUMENT?;
        }

        self.parse_long_arg()!;
        self._ctx.cpidx++;
        self._ctx.argv = self._ctx.argv[1..];
    }

    self.options_ensure_required()!;

    // excludes argv[0] (program name)
    self.arguments = argv[self._ctx.cpidx + 1 ..];

    if (self.flags.require_arguments && self.arguments.len == 0) {
        io::printf("Error: positional argument expected\n");
        return ARGPARSE_MISSING_ARGUMENT?;
    }
}

// -----------------------------------------------------------------------------
// Usage output
// -----------------------------------------------------------------------------

fn void? ArgParse.print_usage(&self)
{
    assert(self.options.len > 0, "ArgParse is not properly configured");

    io::printf("\nUsage:\n");
    if (self.usage) {
        @pool() {
            // prepend program_name to each usage line
            path::Path path = path::temp(self.program_name)!;
            foreach (usage : self.usage.tsplit("\n")) {
                usage = usage.trim();
                if (!usage) {
                    continue;
                }
                io::printf("%s %s\n", path.basename(), usage);
            }
            io::print("\n");
        };
    } else {
        io::printf("%s [options] [--] [arg1 argN]\n", self.program_name);
    }

    if (self.description) {
        io::printf("%s\n", self.description);
    }

    usz usage_opts_width = 0;
    foreach (opt : self.options) {
        usz len = 0;
        if (opt.short_name) {
            len += 2;
            if (opt.long_name) len += 2;  // extra for ", "
        }
        if (opt.long_name) {
            len += opt.long_name.len + 2;
        }

        if (opt.value) {
            switch (opt.value.type) {
                case int.typeid:
                case uint.typeid:
                case long.typeid:
                case ulong.typeid:
                    len += 6;  // "=<int>"
                case float.typeid:
                case double.typeid:
                    len += 6;  // "=<flt>"
                case String.typeid:
                    len += 6;  // "=<str>"
            }
        }

        len = (len + 3) - ((len + 3) & 3);
        if (usage_opts_width < len) {
            usage_opts_width = len;
        }
    }
    usage_opts_width += 4;  // 4 spaces prefix

    foreach (opt : self.options) {
        usz pos = 0;
        usz pad = 0;
        if (opt._arg_type == ArgType.GROUP) {
            io::printf("\n%s\n", opt.help);
            continue;
        }
        pos = io::printf("    ")!;
        if (opt.short_name) {
            pos += io::printf("-%c", opt.short_name)!;
        }
        if (opt.long_name && opt.short_name) {
            pos += io::printf(", ")!;
        }
        if (opt.long_name) {
            pos += io::printf("--%s", opt.long_name)!;
        }
        if (opt.value) {
            switch (opt.value.type) {
                case short.typeid:
                case ushort.typeid:
                case int.typeid:
                case uint.typeid:
                case long.typeid:
                case ulong.typeid:
                    pos += io::printf("=<int>")!;
                case float.typeid:
                case double.typeid:
                    pos += io::printf("=<flt>")!;
                case String.typeid:
                    pos += io::printf("=<str>")!;
            }
        }

        if (pos <= usage_opts_width) {
            pad = usage_opts_width - pos;
        } else {
            io::print("\n");
            pad = usage_opts_width;
        }
        io::printf("%*s%s", (int)pad + 2, "", opt.help);
        if (!opt.required) {
            if (opt.value) {
                switch (opt.value.type) {
                    case bool.typeid:
                    case short.typeid:
                    case ushort.typeid:
                    case int.typeid:
                    case uint.typeid:
                    case long.typeid:
                    case ulong.typeid:
                    case float.typeid:
                    case double.typeid:
                    case String.typeid:
                        io::printf(" [default: %s]", opt.value);
                    default:
                        // custom value with callback
                        break;
                }
            }
        } else {
            io::printf(" (required)");
        }
        io::print("\n");
    }
    if (self.epilog) {
        io::printf("\n%s\n", self.epilog);
    }
}

// -----------------------------------------------------------------------------
// Internal helpers
// -----------------------------------------------------------------------------

fn void? ArgParse.options_ensure_required(&self) @local
{
    bool has_errors = false;
    foreach (i, opt : self.options) {
        if (opt._arg_type == ArgType.GROUP || opt._arg_type == ArgType.HELP) {
            continue;
        }

        if (opt.required && !opt._is_present) {
            io::printf("Error: missing required option: -%c/--%s\n",
                       opt.short_name, opt.long_name);
            has_errors = true;
        }
    }
    if (has_errors) {
        return ARGPARSE_MISSING_ARGUMENT?;
    }
}

fn void? ArgParse.options_check(&self) @local
{
    assert(self.arguments.len == 0, "already processed?");

    foreach (i, opt : self.options) {
        if (opt._arg_type == ArgType.GROUP || opt._arg_type == ArgType.HELP) {
            continue;
        }

        if (!(opt.short_name || opt.long_name)) {
            unreachable("option[%d] both long/short_name are not set", i);
        }
        if (!opt.value && !opt.callback) {
            unreachable(
                "option[%d][-%c/--%s] has no valid .value pointer or .callback set",
                i,
                opt.short_name,
                opt.long_name
            );
        }

        if (opt.allow_many) {
            if (!opt.callback) {
                if (opt.value.type != int.typeid) {
                    unreachable(
                        "option[%d][-%c/--%s] has .allow_many=true, without .callback, "
                        "only int type .value supported for accumulator flags",
                        i,
                        opt.short_name,
                        opt.long_name
                    );
                }
            }
        }

        if (opt.value) {
            switch (opt.value.type) {
                case bool.typeid:
                case uint.typeid:
                case long.typeid:
                case ulong.typeid:
                case float.typeid:
                case double.typeid:
                case String.typeid:
                case int.typeid:
                    // resetting presence flag, updated after parsing
                    opt._is_present = false;
                default:
                    if (!opt.callback) {
                        unreachable(
                            "option[%d][-%c/--%s] type[%s] is not supported (or pass .callback)",
                            i,
                            opt.short_name,
                            opt.long_name,
                            opt.value.type
                        );
                    }
            }
        }
    }
}

fn String? ArgParse.get_arg(&self) @local
{
    if (self._ctx.optvalue) {
        // --arg=<optvalue> via '='
        String result = self._ctx.optvalue;
        self._ctx.optvalue = "";
        return result;
    } else if (self._ctx.argv.len > 1) {
        self._ctx.argv = self._ctx.argv[1..];
        self._ctx.cpidx++;
        String result = self._ctx.argv[0];
        if (!result || result[0] == '-') {
            io::printf(
                "Error: getting another option instead of previous option value at `%s`\n",
                self._ctx.argv[0]
            );
            return ARGPARSE_ARGUMENT_VALUE?;
        }
        return result;
    } else {
        io::printf("Error: missing argument value for %s\n", self._ctx.argv[0]);
        return ARGPARSE_ARGUMENT_VALUE?;
    }
}

fn void? ArgParse.parse_arg_val(&self, ArgOpt* opt, bool flag_unset = false) @local
{
    assert(opt);
    if (opt._arg_type == ArgType.HELP) {
        return ARGPARSE_HELP_SHOW?;
    }

    if (opt._is_present && !opt.allow_many) {
        io::printf("Error: duplicated option %s\n", self._ctx.argv[0]);
        return ARGPARSE_INVALID_ARGUMENT?;
    }

    // callback path: ctx is opt.value
    if (opt.callback) {
        if (opt.value && (opt.value.type == bool.typeid ||
                          (opt.allow_many && opt.value.type == int.typeid))) {
            opt.callback(opt.value, flag_unset ? "0" : "1")!;
        } else {
            String aval = self.get_arg()!;
            opt.callback(opt.value, aval)!;
        }
        opt._is_present = true;
        return;
    }

    // value-based path
    assert(opt.value);

    if (opt.value.type != bool.typeid) {
        assert(!flag_unset, "flag_unset only for bool options");
    }

    opt._is_present = true;

    switch (opt.value.type) {
        case bool.typeid: {
            bool* pvalue = anycast(opt.value, bool)!;
            *pvalue = flag_unset ? false : true;
        }
        case String.typeid:
            *anycast(opt.value, String)! = self.get_arg()!;
        case int.typeid:
            if (opt.allow_many) {
                // ints in allow_many act as accumulator flags
                *anycast(opt.value, int)! += 1;
            } else {
                String aval = self.get_arg()!;
                *anycast(opt.value, int)! = aval.to_integer(int)!;
            }
        case uint.typeid: {
            String aval = self.get_arg()!;
            *anycast(opt.value, uint)! = aval.to_integer(uint)!;
        }
        case long.typeid: {
            String aval = self.get_arg()!;
            *anycast(opt.value, long)! = aval.to_integer(long)!;
        }
        case ulong.typeid: {
            String aval = self.get_arg()!;
            *anycast(opt.value, ulong)! = aval.to_integer(ulong)!;
        }
        case float.typeid: {
            String aval = self.get_arg()!;
            *anycast(opt.value, float)! = aval.to_float()!;
        }
        case double.typeid: {
            String aval = self.get_arg()!;
            *anycast(opt.value, double)! = aval.to_double()!;
        }
        default:
            unreachable("TODO: implement this typeid: %s", opt.value.type.kindof);
    }
}

fn void? ArgParse.parse_short_arg(&self) @local
{
    foreach (&opt : self.options) {
        if (opt.short_name == self._ctx.optvalue[0]) {
            self._ctx.optvalue =
                self._ctx.optvalue.len > 1 ? self._ctx.optvalue[1..] : "";
            if (catch err = self.parse_arg_val(opt, false)) {
                switch (err) {
                    case ARGPARSE_MISSING_ARGUMENT:
                    case ARGPARSE_INVALID_ARGUMENT:
                    case ARGPARSE_ARGUMENT_VALUE:
                    case ARGPARSE_CONFIGURATION:
                    case ARGPARSE_HELP_SHOW:
                        return err?;
                    default:
                        io::printf(
                            "Error: argument parse error -%c failed with `%s`\n",
                            opt.short_name, err
                        );
                        return ARGPARSE_ARGUMENT_VALUE?;
                }
            }
            return;  // ALL OK
        }
    }
    io::printf("Error: invalid argument %s\n", self._ctx.argv[0]);
    return ARGPARSE_INVALID_ARGUMENT?;
}

fn String? prefix_skip(String s, String prefix) @local
{
    if (s.starts_with(prefix)) {
        return s[prefix.len ..];
    } else {
        return ARGPARSE_MISSING_ARGUMENT?;
    }
}

fn void? ArgParse.parse_long_arg(&self) @local
{
    foreach (&opt : self.options) {
        if (!opt.long_name) {
            continue;
        }

        bool flag_unset = false;
        String? arg = prefix_skip(self._ctx.argv[0][2..], opt.long_name);
        if (catch err = arg) {
            switch (err) {
                case ARGPARSE_MISSING_ARGUMENT:
                    // for boolean flags support `--no-<flag_name>`
                    if (
                        opt.value &&
                        opt.value.type == bool.typeid &&
                        self._ctx.argv[0][2..].starts_with("no-") &&
                        self._ctx.argv[0][5..].starts_with(opt.long_name)
                    ) {
                        flag_unset = true;
                    } else {
                        continue;
                    }
                default:
                    unreachable();
            }
        } else {
            if (arg && arg[0] == '=') {
                self._ctx.optvalue = arg[1..];
            }
        }

        if (catch err = self.parse_arg_val(opt, flag_unset)) {
            switch (err) {
                case ARGPARSE_MISSING_ARGUMENT:
                case ARGPARSE_INVALID_ARGUMENT:
                case ARGPARSE_ARGUMENT_VALUE:
                case ARGPARSE_CONFIGURATION:
                case ARGPARSE_HELP_SHOW:
                    return err?;
                default:
                    io::printf(
                        "Error: argument parse error %s failed with `%s`\n",
                        self._ctx.argv[0], err
                    );
                    return ARGPARSE_ARGUMENT_VALUE?;
            }
        }
        return;  // ALL OK
    }

    io::printf("Error: invalid argument %s\n", self._ctx.argv[0]);
    return ARGPARSE_INVALID_ARGUMENT?;
}
