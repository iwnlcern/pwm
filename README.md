# PWM (lightweight C3 password manager)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![C3](https://img.shields.io/badge/C3-0.7.7-orange.svg)](https://c3-lang.org)

Simple, lightweight CLI password manager written in C3. It stores credentials in encrypted SQLite databases (SQLCipher) under `~/Documents/pwm/` by default (e.g., `pwm_db.db`), lets you point to custom locations, and copies retrieved passwords to your clipboard with an auto-clear after 10 seconds. 

Note that PWM is best protected against shoulder peeking, screen recorders, and other unsophisticated attack methods. No guarantees against advanced attack methods like memory dumps and the such; minimal protection given by ensuring memory holding passwords and other confidential information is cleared by zeroing out; however, passwords may still persist in clipboard history. I am not aware of any software workarounds that can output passwords in a more secure manner. The most secure option I can think of is having the database loaded into a thumbdrive and then use an offline device to view confidential information. This should provide sufficent security for most people.

**It goes without saying that if someone wants your data bad enough, they will be able to find a way to get it.** ***USE AT YOUR OWN RISK.***

## Features
- Create encrypted vaults backed by SQLCipher.
- Add/update (`--update`/`-u` or `--add`/`-a`) and remove (`--remove`/`-r`) entries keyed by site + username.
- Retrieve entries (`--get`/`-g`), print metadata, and copy the password to the clipboard.
- Cross-platform clipboard support: `pbcopy` (macOS), `wl-copy` or `xclip` (Linux), `clip` (Windows).
- Clear clipboard after a short delay (10 seconds) via a background job.
- Track multiple vaults: use `--db-name` for alternative names under `~/Documents/pwm/` or `--db-path` for arbitrary locations.
- Fuzzy name matching: suggests the closest tracked vault name when an exact match isn't found.
- Master registry database (unencrypted) remembers known vault paths and auto-prunes entries for missing files.
- Secure password input with terminal echo disabled.
- Passwords are wiped from memory after use.

## Requirements
- C3 compiler (v0.7.7 or later). Build expects `c3c`.
- SQLCipher/SQLite3 headers and libraries. Default linker search path is `/opt/homebrew/opt/sqlcipher/lib`—adjust `project.json` if your installation differs.
- Clipboard tools:
  - macOS: `pbcopy`
  - Linux: `wl-copy` (preferred) or `xclip`
  - Windows: built-in `clip` + PowerShell for timed clear
- `HOME` environment variable set (used to place the vault in `~/Documents/pwm/`).

## Build
From the repo root:

```sh
c3c build pwm          # builds to ./build/pwm
# or run directly
c3c run pwm -- --help  # pass args after --
```

## Usage
The CLI expects exactly one action flag:

| Flag | Short | Description |
|------|-------|-------------|
| `--init` | | Create a new encrypted DB (default: `~/Documents/pwm/pwm_db.db`). Prompts for vault password. |
| `--update` | `-u` | Insert/update an entry. Use with `--site` and `--user`; prompts for credential password. |
| `--add` | `-a` | Alias for `--update`. |
| `--remove` | `-r` | Delete an entry by site and username. |
| `--get` | `-g` | Show site/user and copy password to clipboard (auto-clears after 10s). |
| `--list-dbs` | | Show tracked database names and paths. |

Database selection:
- `--db-name`             Name of the DB file under `~/Documents/pwm/` (default: `pwm_db.db`). The `.db` extension is added automatically if omitted (e.g., `--db-name work` becomes `work.db`). If multiple tracked DBs share the name, all paths are printed and the command aborts so you can re-run with `--db-path`. If no tracked match exists, the closest tracked name is suggested and the default path is used when it exists.
- `--db-path`             Full path to a DB file; overrides `--db-name` and registry lookup. Allows databases with the same filename in different locations. You can also pass the path as the final positional argument (e.g., `--init /path/to/db`).

Supporting options:
- `--site` / `--service`   Site/service name.
- `--user`                 Username for the entry.
- `--help` / `-h`          Show help and usage.

Examples:

```sh
# One-time initialization (default path ~/Documents/pwm/pwm_db.db)
./build/pwm --init

# Initialize a second vault with a custom name under ~/Documents/pwm/
./build/pwm --init --db-name work_secrets  # creates work_secrets.db

# Initialize a vault at an explicit path
./build/pwm --init --db-path /Users/me/Desktop/my_secrets.db
# or use the positional shorthand for the path
./build/pwm --init /Users/me/Desktop/my_secrets.db

# Add or update an entry
./build/pwm --update --site example.com --user alice

# Fetch an entry (prints site/user, copies password, clears clipboard after 10s)
./build/pwm --get --site example.com --user alice

# Remove an entry
./build/pwm --remove --site example.com --user alice
```

## Multiple vaults & registry
- A master registry is stored at `~/Documents/pwm/pwm_master_db.db` (unencrypted). It records vault name → path mappings and requires no password.
- On every run, the registry is ensured to exist and prunes entries for files that no longer exist.
- Multiple databases can have the same filename in different locations (e.g., `~/work/secrets.db` and `~/personal/secrets.db`).
- Name resolution for `--db-name`: if multiple tracked entries share the name, the one in the default directory (`~/Documents/pwm/`) is preferred. If none are in the default directory, their paths are printed and the command exits so you can re-run with `--db-path`. If none are tracked, the closest tracked name is suggested.
- Using `--db-path` bypasses name resolution entirely and accesses the database directly.
- After successful operations, the selected vault path is re-registered so the registry stays current.
- Each vault has its own password; the registry does not reuse a shared password.
- To use a vault created elsewhere, point to it with `--db-path` and supply that vault's password.

## Data & security notes
- Default vault path: `~/Documents/pwm/pwm_db.db` (override with `--db-name`/`--db-path`). Each vault has its own password; losing it means losing access to that vault.
- Master registry lives at `~/Documents/pwm/pwm_master_db.db`, only stores vault names/paths, and is unencrypted.
- Encryption relies on SQLCipher via `sqlite3_key`; integrity is checked with `PRAGMA cipher_integrity_check`.
- Clipboard clearing is best-effort via a background process; behavior depends on OS clipboard tooling being present. **NOTE: May still be present in clipboard history.**
- 
## TODOs:
- Add tests (PLS)
- Option for displaying password in terminal in tty mode.
- Looking to display all usernames for a given site.
- Maybe also store security questions and answers.
- Perhaps a GUI interface sometime in the future when c3 is more mature.

## Acknowledgements
- CODEX 5.1 and CLAUDE OPUS 4.5 for all the documentation and markdown files (I cba to write, easier to read and verify) and boiler-plate.
- Alex Veden (<i@alexveden.com>) for argparse.c3 original src and CODEX for updates.

## License
This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
