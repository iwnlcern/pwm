module pwm;

import std::io;
import std::io::path;
import libc;
import misc::argparse;
import misc::termios;
import misc::secure;

import pwm::vault;
import db;

const String DEFAULT_DB_NAME = "pwm_db.db";
const String MASTER_DB_NAME  = "pwm_master_db.db";

fn String get_secure_pw(ZString msg) {
    termios::Termios oflags, nflags;
    int fd = libc::STDIN_FD;
    
    if (termios::tcgetattr(fd, &oflags) != 0) {
        io::eprintf("tcgetattr failed");
        libc::exit(1);
    }

    nflags = oflags;
    nflags.c_lflag &= ~termios::ECHO;
    nflags.c_lflag |= termios::ECHONL;
    if (termios::tcsetattr(fd, termios::TCSANOW, &nflags) != 0) {
        io::eprintf("tcsetattr (disable echo) failed");
        libc::exit(1);
    }

    defer {
        if (termios::tcsetattr(fd, termios::TCSANOW, &oflags) != 0) {
            io::eprint("tcsetattr (restore) failed");
        }
    }

    io::printf(msg.str_view());
    char[64] buf;
    secure::explicit_bzero(&buf[0], 64);

    if (libc::fgets(&buf[0], buf.len, libc::stdin()) == null) {
        io::eprintfn("fgets failed reading password");
        libc::exit(1);
    }

    String str_password = ((ZString) &buf[0]).str_view();
    defer secure::wipe_string(str_password);

    if (str_password.len > 0 && str_password[str_password.len - 1] == '\n') {
        str_password = str_password[..str_password.len - 1];
    }

    return str_password.tcopy();
}


fn ZString? get_db_path(String db_name) {
    ZString home = libc::getenv("HOME");
    if (home == null) {
        io::eprintfn("HOME not set");
        return null;
    }

    String str_home = home.str_view();
    str_home = str_home.tconcat("/Documents/pwm/");

    String str_db_path = str_home.tcopy();
    str_db_path = str_db_path.tconcat(db_name);
    ZString db_path = str_db_path.zstr_tcopy();
    return db_path;
}

fn ZString? make_home_dir(String db_name) {
    ZString home = libc::getenv("HOME");
    if (home == null) {
        io::eprintfn("HOME not set");
        return null;
    }

    String str_home = home.str_view();
    str_home = str_home.tconcat("/Documents/pwm/");

    if (catch excuse = io::path::mkdir(str_home.to_tpath())) {
        if (!io::path::exists(str_home.to_tpath())!) {
            io::eprintfn("mkdir('%s') failed: %s", str_home, excuse);
            return null;
        }
    }

    String str_db_path = str_home.tcopy();
    str_db_path = str_db_path.tconcat(db_name);
    ZString db_path = str_db_path.zstr_tcopy();
    return db_path;
}

fn String filename_from_path(String db_path_str) {
    if (!db_path_str || db_path_str.len == 0) {
        return "";
    }

    int last_sep = -1;
    for (int i = (int) db_path_str.len - 1; i >= 0; i--) {
        char c = db_path_str[i];
        if (c == '/' || c == '\\') {
            last_sep = i;
            break;
        }
    }

    return db_path_str[last_sep + 1 ..].tcopy();
}

fn String ensure_db_extension(String name) {
    if (!name || name.len == 0) {
        return name;
    }
    if (name.ends_with(".db")) {
        return name;
    }
    return name.tconcat(".db");
}

fn bool enforce_db_name_matches_filename(String *db_name,
                                         String db_path_str,
                                         bool db_name_flag_present) {
    String filename = filename_from_path(db_path_str);
    if (!filename || filename.len == 0) {
        io::eprintfn("Database path '%s' must include a filename.", db_path_str);
        return false;
    }

    if (db_name_flag_present && *db_name != filename) {
        io::eprintfn("--db-name ('%s') must match the database filename '%s'.", *db_name, filename);
        return false;
    }

    *db_name = filename;
    return true;
}

struct Credentials {
    String site;
    String user;
}

fn int main(String[] args) {
    // One bool per top-level action
    bool do_init   = false;
    bool do_update = false;
    bool do_remove = false;
    bool do_get    = false;
    bool do_list_dbs = false;

    Credentials credentials = {
        .site = "",
        .user = "",
    };

    String db_name          = DEFAULT_DB_NAME;
    String db_path_override = "";

    argparse::ArgParse agp = {
        .description = "Simple, lightweight cross-platform CLI password manager written in C3.",
        .usage       = "[--init|--update|--remove|--get] [--site <site>] [--user <user>] [--db-name <name>|--db-path <path>|<db-path>]",
        .epilog      = "Run --init once to create a database (default: ~/Documents/pwm/pwm_db.db); append --db-name or --db-path to access exact db. Note, all passwords must fit within 64 characters.",
        .options     = {
            argparse::help_opt(),
            argparse::group_opt("Basic options"),

            {
                .long_name  = "init",
                .value      = &do_init,      // bool
                .help       = "Initializes or mounts a database. Do this first before using.",
            },
            {
                .short_name = 'u',
                .long_name  = "update",
                .value      = &do_update,    // bool
                .help       = "Add or update an entry. Use with --site and --user.",
            },
            {
                .short_name = 'a',
                .long_name  = "add",
                .value      = &do_update,    // alias for --update
                .help       = "Alias for --update.",
            },
            {
                .short_name = 'r',
                .long_name  = "remove",
                .value      = &do_remove,    // bool
                .help       = "Removes an entry given site and username.",
            },
            {
                .short_name = 'g',
                .long_name  = "get",
                .value      = &do_get,       // bool
                .help       = "Retrieves username and password after master password check.",
            },
            {
                .long_name  = "list-dbs",
                .value      = &do_list_dbs,
                .help       = "List tracked databases and their paths.",
            },

            argparse::group_opt("Database selection"),
            {
                .long_name  = "db-name",
                .value      = &db_name,
                .help       = "Name of the database file under ~/Documents/pwm/ (default: pwm_db.db). The .db extension is added automatically if omitted.",
            },
            {
                .long_name  = "db-path",
                .value      = &db_path_override,
                .help       = "Full path to a database file; overrides --db-name and registry lookup. You can also pass the path as a positional argument.",
            },

            argparse::group_opt("Entry selection"),
            {
                .long_name  = "site",
                .value      = &credentials.site,
                .help       = "Site where account is.",
            },
            {
                .long_name  = "service",
                .value      = &credentials.site,  // alias for --site
                .help       = "Alias for --site.",
            },
            {
                .long_name  = "user",
                .value      = &credentials.user,
                .help       = "Username for the account.",
            },
        },
    };

    if (catch err = agp.parse(args)) {
        agp.print_usage()!!;
        // You *can* special-case a help fault if you want,
        // but for now just treat any error as exit 1.
        return 1;
    }

    int num_actions =
        (do_init     ? 1 : 0) +
        (do_update   ? 1 : 0) +
        (do_remove   ? 1 : 0) +
        (do_get      ? 1 : 0) +
        (do_list_dbs ? 1 : 0);

    if (num_actions == 0) {
        io::eprintfn("No action specified. Use --init, --update, --remove, --get, or --list-dbs.");
        agp.print_usage()!!;
        return 1;
    }
    if (num_actions > 1) {
        io::eprintfn("Specify exactly one of --init, --update/--add, --remove, --get, or --list-dbs.");
        return 1;
    }

    bool db_name_flag_present = false;
    foreach (opt : agp.options) {
        if (opt.long_name && opt.long_name == "db-name") {
            db_name_flag_present = opt._is_present;
            break;
        }
    }

    if (agp.arguments.len > 0) {
        if (db_path_override && db_path_override.len > 0) {
            io::eprintfn("Unexpected positional argument(s). Use only one database path or the --db-path flag.");
            return 1;
        }
        if (agp.arguments.len > 1) {
            io::eprintfn("Too many positional arguments. Provide a single database path or use --db-path.");
            return 1;
        }
        db_path_override = agp.arguments[0];
    }

    String selected_db_name = db_name;
    if (!selected_db_name || selected_db_name.len == 0) {
        selected_db_name = DEFAULT_DB_NAME;
    }
    selected_db_name = ensure_db_extension(selected_db_name);

    ZString master_db_path = make_home_dir(MASTER_DB_NAME)!!;
    if (vault::ensure_master_registry(master_db_path) != db::SQLITE_OK) {
        return 1;
    }
    if (vault::prune_missing_databases(master_db_path) != db::SQLITE_OK) {
        return 1;
    }

    if (do_list_dbs) {
        vault::list_databases(master_db_path);
        return 0;
    }

    if (do_init) {
        ZString init_db_path = null;
        if (db_path_override && db_path_override.len > 0) {
            init_db_path = db_path_override.zstr_tcopy();
        } else {
            init_db_path = make_home_dir(selected_db_name)!!;
        }
        String init_db_path_str = init_db_path.str_view();
        if (!enforce_db_name_matches_filename(&selected_db_name, init_db_path_str, db_name_flag_present)) {
            return 1;
        }

        String vault_pw = get_secure_pw("Enter vault password (64 char max): ");
        defer secure::wipe_string(vault_pw);

        if (vault::create_vault(vault_pw, init_db_path) != db::SQLITE_OK) {
            return 1;
        }
        if (vault::register_database(master_db_path, selected_db_name, init_db_path) != db::SQLITE_OK) {
            return 1;
        }
        (void) vault::prune_missing_databases(master_db_path);
        return 0;
    }

    ZString db_path = null;
    if (db_path_override && db_path_override.len > 0) {
        db_path = db_path_override.zstr_tcopy();
    } else {
        vault::DbPathMatches matches = vault::lookup_database_paths(master_db_path, selected_db_name);
        if (matches.len > 1) {
            io::eprintfn("Multiple databases named '%s' found. Use --db-path to pick one:", selected_db_name);
            for (int i = 0; i < matches.len; i++) {
                io::eprintfn("  %s", matches.paths[i]);
            }
            return 1;
        }
        if (matches.len == 1) {
            db_path = matches.paths[0];
        } else {
            vault::ClosestDbMatch closest = vault::closest_database_match(master_db_path, selected_db_name);
            if (closest.found) {
                io::printf("No tracked database named '%s'. Closest tracked: '%s' at %s\n",
                           selected_db_name, closest.name, closest.path);
            } else {
                io::printf("No tracked database named '%s'.\n", selected_db_name);
            }

            ZString default_db_path = get_db_path(selected_db_name)!!;
            if (path::exists(default_db_path.str_view().to_tpath())!!) {
                io::printf("Using default path %s\n", default_db_path);
                db_path = default_db_path;
            } else {
                io::eprintfn("No database found for '%s'. Use --db-path or initialize it with --init.", selected_db_name);
                return 1;
            }
        }
    }

    if (db_path == null) {
        io::eprintfn("Unable to resolve database path.");
        return 1;
    }

    String db_path_str = db_path.str_view();
    if (!enforce_db_name_matches_filename(&selected_db_name, db_path_str, db_name_flag_present)) {
        return 1;
    }
    if (!path::exists(db_path_str.to_tpath())!!) {
        io::eprintfn("Database not found at %s", db_path_str);
        return 1;
    }

    String vault_pw = get_secure_pw("Enter vault password (64 char max): ");
    defer secure::wipe_string(vault_pw);

    if (do_update) {
        String cred_pw = get_secure_pw("Enter credential password (64 char max): ");
        defer secure::wipe_string(cred_pw);
        if (vault::update_credentials(
                vault_pw,
                db_path,
                credentials.site.zstr_tcopy(),
                credentials.user.zstr_tcopy(),
                cred_pw) != db::SQLITE_OK) {
            return 1;
        }
        if (vault::register_database(master_db_path, selected_db_name, db_path) != db::SQLITE_OK) {
            return 1;
        }
        return 0;
    }

    if (do_remove) {
        if (vault::remove_credentials(
                vault_pw,
                db_path,
                credentials.site.zstr_tcopy(),
                credentials.user.zstr_tcopy()) != db::SQLITE_OK) {
            return 1;
        }
        if (vault::register_database(master_db_path, selected_db_name, db_path) != db::SQLITE_OK) {
            return 1;
        }
        return 0;
    }

    if (do_get) {
        if (vault::return_credentials(
                vault_pw,
                db_path,
                credentials.site.zstr_tcopy(),
                credentials.user.zstr_tcopy()) != db::SQLITE_OK) {
            return 1;
        }
        if (vault::register_database(master_db_path, selected_db_name, db_path) != db::SQLITE_OK) {
            return 1;
        }
        return 0;
    }

    // Should be unreachable
    return 0;
}
