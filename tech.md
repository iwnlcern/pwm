# PWM Technical Documentation

This document describes the internal architecture, module structure, and implementation details of the PWM password manager.

## Architecture Overview

PWM is structured as a modular C3 application with clear separation of concerns:

```
src/
├── main.c3      # Entry point, CLI flow, argument setup
├── argparse.c3  # Generic argument parsing library
├── db.c3        # SQLite/SQLCipher FFI bindings
├── vault.c3     # Database operations and registry management
├── secure.c3    # Security utilities (clipboard, memory wiping)
└── termios.c3   # Terminal I/O bindings for secure input
```

## Module Details

### main.c3 (module: `pwm`)

The entry point that orchestrates all operations:

- **Argument Parsing**: Configures `ArgParse` with action flags (`--init`, `--update`, `--get`, `--remove`, `--list-dbs`) and supporting options.
- **Secure Password Input**: Uses `get_secure_pw()` which disables terminal echo via termios to securely read passwords.
- **Path Resolution**: Handles `--db-name` vs `--db-path` logic, enforcing that database names match filenames.
- **Registry Management**: Ensures the master registry exists and prunes stale entries on every run.
- **Action Dispatch**: Routes to the appropriate vault operation based on the selected action.

Key functions:
| Function | Purpose |
|----------|---------|
| `get_secure_pw()` | Reads password with echo disabled |
| `get_db_path()` | Constructs default DB path from name |
| `make_home_dir()` | Creates `~/Documents/pwm/` if needed |
| `filename_from_path()` | Extracts filename from a path |
| `enforce_db_name_matches_filename()` | Validates name/path consistency |

### db.c3 (module: `db`)

Provides C bindings for SQLite3/SQLCipher:

- **Struct Definitions**: `Sqlite3`, `Sqlite3Stmt` (opaque handles)
- **Result Codes**: All standard SQLite result codes (`SQLITE_OK`, `SQLITE_ROW`, `SQLITE_DONE`, etc.)
- **Core Functions**: `sqlite3_open`, `sqlite3_close`, `sqlite3_exec`, `sqlite3_prepare_v2`, `sqlite3_step`, `sqlite3_finalize`
- **Binding Functions**: `sqlite3_bind_text`, `sqlite3_bind_int64`
- **Retrieval Functions**: `sqlite3_column_text`, `sqlite3_column_int64`

This module contains no application logic - it's purely a Foreign Function Interface (FFI) layer.

### vault.c3 (module: `pwm::vault`)

Core database operations for credential and registry management:

**Database Opening**:
- `open_plain()`: Opens unencrypted databases (for the master registry)
- `open()`: Opens encrypted databases with SQLCipher key derivation

**Credential Operations**:
| Function | SQL Operation |
|----------|---------------|
| `create_vault()` | Creates the `passwords` table with `(site, username, password)` |
| `update_credentials()` | `INSERT ... ON CONFLICT DO UPDATE` (upsert) |
| `remove_credentials()` | `DELETE WHERE site = ? AND username = ?` |
| `return_credentials()` | `SELECT` + clipboard copy |

**Registry Operations**:
| Function | Purpose |
|----------|---------|
| `ensure_master_registry()` | Creates `tracked_databases` table if missing |
| `register_database()` | Records vault path with conflict detection |
| `lookup_database_paths()` | Finds all paths for a given database name |
| `closest_database_match()` | Fuzzy matching using character distance |
| `prune_missing_databases()` | Removes entries for deleted files |
| `list_databases()` | Displays all tracked vaults |

**Schema**:
```sql
-- Encrypted vault (per-database)
CREATE TABLE passwords (
    site     TEXT NOT NULL,
    username TEXT NOT NULL,
    password TEXT NOT NULL,
    PRIMARY KEY (site, username)
);

-- Master registry (unencrypted, ~/Documents/pwm/pwm_master_db)
CREATE TABLE tracked_databases (
    name       TEXT NOT NULL,
    path       TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
```

### secure.c3 (module: `misc::secure`)

Security-critical utilities:

**Memory Wiping**:
- `explicit_bzero()`: Zeroes memory (marked `@noinline` to prevent compiler optimization)
- `wipe_string()`: Wipes a string's backing buffer

**Clipboard Operations**:
- `copy_to_clipboard()`: Platform-specific clipboard write
  - macOS: `pbcopy`
  - Linux: `wl-copy` (preferred) or `xclip` (fallback)
  - Windows: `clip`
- `schedule_clipboard_clear()`: Spawns background process to clear clipboard after 10 seconds
- `output_pw()`: Combines copy + scheduled clear

The clipboard clear uses platform-specific approaches:
- macOS/Linux: `sh -c "sleep 10; printf '' | <clipboard-tool> &"`
- Windows: PowerShell `Start-Job` with `Start-Sleep`

### termios.c3 (module: `misc::termios`)

POSIX terminal I/O bindings for controlling terminal behavior:

- **Constants**: `TCSANOW`, `ECHO`, `ECHONL`, etc.
- **Struct**: `Termios` matching the C `struct termios`
- **Functions**: `tcgetattr`, `tcsetattr`, `tcdrain`, `tcflow`, `tcflush`

Used by `get_secure_pw()` in main.c3 to disable echo during password entry.

### argparse.c3 (module: `misc::argparse`)

A complete argument parsing library (authored by Alex Veden, original [here](https://github.com/alexveden/c3tools/blob/main/lib/c3lib/argparse/argparse.c3), updated for C3 v0.7.7):

**Key Types**:
- `ArgParse`: Top-level parser configuration
- `ArgOpt`: Individual option descriptor
- `ArgParseFlags`: Parser behavior modifiers

**Features**:
- Short (`-u`) and long (`--update`) options
- Boolean flags and value options (string, int, float)
- Grouped help output
- `--no-<flag>` negation for booleans
- Stacked short options (`-abc` = `-a -b -c`)
- Positional argument collection
- Required option validation
- Custom callbacks for complex parsing

**Faults**:
- `ARGPARSE_MISSING_ARGUMENT`
- `ARGPARSE_INVALID_ARGUMENT`
- `ARGPARSE_ARGUMENT_VALUE`
- `ARGPARSE_CONFIGURATION`
- `ARGPARSE_HELP_SHOW`

## Security Considerations

### Encryption
- Vaults use SQLCipher with `sqlite3_key()` for encryption
- Integrity verified via `PRAGMA cipher_integrity_check`
- Each vault has an independent password

### Memory Handling
- Passwords read into fixed-size stack buffers
- `explicit_bzero()` wipes sensitive data
- `defer` blocks ensure cleanup on all exit paths
- `@noinline` prevents compiler from optimizing out wipes

### Password Input
- Terminal echo disabled via `tcsetattr()` with `~ECHO`
- Original terminal state restored via `defer` block
- Newline echo enabled (`ECHONL`) for UX

### Clipboard Security
- Passwords never printed to stdout
- Automatic clipboard clear after 10 seconds
- Background process handles delayed clear

## Build Configuration

The project uses a `project.json` for C3's build system:

```sh
c3c build pwm      # Build to ./build/pwm
c3c run pwm -- -h  # Run with args
```

**Dependencies**:
- SQLCipher (or SQLite3 with encryption extension)
- Default library path: `/opt/homebrew/opt/sqlcipher/lib` (macOS Homebrew)

## Platform Support

| Platform | Clipboard Tool | Clear Method |
|----------|----------------|--------------|
| macOS | `pbcopy` | `sh -c "sleep 10; printf '' \| pbcopy &"` |
| Linux | `wl-copy` or `xclip` | `sh -c "sleep 10; printf '' \| <tool> &"` |
| Windows | `clip` | PowerShell `Start-Job` |

Clipboard tool detection on Linux checks for `wl-copy` first (Wayland), then `xclip` (X11).

## Data Flow

```
User Input
    │
    ▼
┌──────────────┐
│   main.c3    │  ◄── Argument parsing, flow control
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  vault.c3    │  ◄── Business logic, SQL operations
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   db.c3      │  ◄── SQLite FFI
└──────┬───────┘
       │
       ▼
   SQLCipher
   (encrypted)
```

For credential retrieval, `secure.c3` handles the clipboard output path.
