# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2025-12-14

### Security
- Fixed use-after-close vulnerability: all vault functions now check `open()` return code before using the database handle.
- Fixed password heap leak: credential passwords are now bound with explicit length to avoid extra heap copies that wouldn't be wiped.
- Enabled `PRAGMA secure_delete=ON` to overwrite deleted data with zeros, preventing recovery of old credentials from free pages.
- Replaced all `libc::exit(1)` calls with proper error propagation so `defer` cleanup (including `wipe_string`) runs correctly.
- Added `sqlite3_key()` return code check to detect encryption key failures.
- Set database pointer to `null` after `sqlite3_close()` in all error paths to prevent use-after-close.

### Fixed
- Fixed clipboard clearing blocking the main process for 10 seconds; now spawns a fully detached background process.
- Fixed Linux `xclip` targeting wrong selection; now explicitly uses `-selection clipboard`.
- Fixed resource leak: `sqlite3_open()` failures now properly close the handle before returning.

### Changed
- `get_secure_pw()` now returns `String?` (optional) instead of calling `exit()` on error.
- `close_with_error()` now takes `db::Sqlite3 **` and nulls the pointer after closing.

## [0.1.0] - 2025-12-14

### Added
- Initial release of PWM password manager.
- SQLCipher-encrypted vault storage with per-vault passwords.
- CRUD operations for credentials: `--init`, `--add`/`--update`, `--get`, `--remove`.
- Master registry to track multiple vaults across the filesystem.
- Cross-platform clipboard support (macOS, Linux, Windows).
- Automatic clipboard clearing after 10 seconds.
- Secure password input with terminal echo disabled.
- Memory wiping for sensitive data after use.
- Fuzzy matching for vault name suggestions.
- Auto-append `.db` extension for `--db-name` convenience.
- `--list-dbs` command to show tracked databases.
