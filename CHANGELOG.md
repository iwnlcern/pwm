# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
