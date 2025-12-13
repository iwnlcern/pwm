module pwm;

import std::io;
import libc;
import misc::argparse;
import misc::termios;
import misc::secure;

import pwm::vault;
import db;

fn String get_secure_pw(ZString msg) {
    termios::Termios oflags, nflags;
    int fd = libc::STDIN_FD;
    
    if ( termios::tcgetattr(fd, &oflags) != 0) {
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

    if (catch excuse = io::path::mkdir(str_home)) {
        io::eprintfn("mkdir('%s') failed: %s", str_home, excuse);
        return null;
    }

    String str_db_path = str_home.tcopy();
    str_db_path = str_db_path.tconcat(db_name);
    ZString db_path = str_db_path.zstr_tcopy();
    return db_path;
}

struct Credentials {
    String site;
    String user;
    String pw;
}

fn int main(String[] args)
{
    // One bool per top-level action
    bool do_init   = false;
    bool do_update = false;
    bool do_remove = false;
    bool do_get    = false;

    Credentials credentials = {
        .site = "",
        .user = "",
    };

    argparse::ArgParse agp = {
        .description = "Simple, lightweight CLI password manager written in C3.",
        .usage       = "[--init|--update|--remove|--get] [--site <site>] [--user <user>]",
        .epilog      = "Run --init once to create the database in ~/Documents/pwm/.",
        .options     = {
            argparse::help_opt(),
            argparse::group_opt("Basic options"),

            {
                .long_name  = "init",
                .value      = &do_init,      // bool, auto-set to true
                .help       = "Initializes the database. Do this first before using.",
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
        (do_init   ? 1 : 0) +
        (do_update ? 1 : 0) +
        (do_remove ? 1 : 0) +
        (do_get    ? 1 : 0);

    if (num_actions == 0) {
        io::eprintfn("No action specified. Use --init, --update, --remove or --get.");
        agp.print_usage()!!;
        return 1;
    }
    if (num_actions > 1) {
        io::eprintfn("Specify exactly one of --init, --update/--add, --remove, or --get.");
        return 1;
    }

    String master_pw = get_secure_pw("Enter database password: ");
    defer secure::wipe_string(master_pw);

    if (do_init) {
        ZString db_path = make_home_dir("pwm_db")!!;
        if (vault::create_vault(master_pw, db_path) != db::SQLITE_OK) {
            return 1;
        }
        return 0;
    }

    ZString db_path = get_db_path("pwm_db")!!;

    if (do_update) {
        if (vault::update_credentials(
                master_pw,
                db_path,
                (ZString) credentials.site,
                (ZString) credentials.user,
                get_secure_pw("Enter credential password: ")) != db::SQLITE_OK) {
            return 1;
        }
        return 0;
    }

    if (do_remove) {
        if (vault::remove_credentials(
                master_pw,
                db_path,
                (ZString) credentials.site,
                (ZString) credentials.user) != db::SQLITE_OK) {
            return 1;
        }
        return 0;
    }

    if (do_get) {
        if (vault::return_credentials(
                master_pw,
                db_path,
                (ZString) credentials.site,
                (ZString) credentials.user) != db::SQLITE_OK) {
            return 1;
        }
        return 0;
    }

    // Should be unreachable
    return 0;
}

//    ZString db_path = make_home_dir("pwm_db");
//
//    int rc = vault::create_vault("password", db_path);
//    if ( rc != db::SQLITE_OK ) {
//        return 1;
//    }
//
//    rc = vault::update_password("password", db_path, "test.com", "admin", "admin");
//    if ( rc != db::SQLITE_OK) {
//        return 1;
//    }
//
//    rc = vault::return_password("password", db_path, "test.com", "admin");
//    if ( rc != db::SQLITE_OK) {
//        return 1;
//    }
