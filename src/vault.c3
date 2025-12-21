module pwm::vault;
import std::io;
import std::io::path;
import db;

import misc::secure;
const int MAX_DB_NUM = 32;

struct DbPathMatches {
    ZString[MAX_DB_NUM] paths;
    int len;
}

struct ClosestDbMatch {
    bool found;
    String name;
    ZString path;
    int distance;
}

extern fn int sqlite3_key(db::Sqlite3 *db, void *key, int key_len);

fn int close_with_error(db::Sqlite3 **db, String msg) @local {
    io::eprintf("%s: %s\n", msg, db::sqlite3_errmsg(*db));
    db::sqlite3_close(*db);
    *db = null;
    return db::SQLITE_ERROR;
}

fn int open_plain(ZString filename, db::Sqlite3 **db) @local {
    int rc = db::sqlite3_open(filename, db);
    if (rc) {
        io::eprintf("Can't open database: %s\n", db::sqlite3_errmsg(*db));
        db::sqlite3_close(*db);
        *db = null;
        return rc;
    }
    return rc;
}

fn int open(String master_pw,
            ZString filename,
            db::Sqlite3 **db) @local {

    int rc = db::sqlite3_open(filename, db);

    if (rc) {
        io::eprintf("Can't open database: %s\n", db::sqlite3_errmsg(*db));
        db::sqlite3_close(*db);
        *db = null;
        return rc;
    }

    void *key_ptr = master_pw.ptr;
    int key_len = (int) master_pw.len;

    rc = sqlite3_key(*db, key_ptr, key_len);
    if (rc != db::SQLITE_OK) {
        return close_with_error(db, "Failed to set encryption key");
    }

    ZString check_sql = "PRAGMA cipher_integrity_check;";
    ZString err_msg = null;

    rc = db::sqlite3_exec(*db, check_sql, null, null, &err_msg);
    if (rc != db::SQLITE_OK) {
        if (err_msg != null) {
            io::eprintf("Wrong password or corrupt DB: %s\n", err_msg);
            db::sqlite3_free(err_msg);
        }
        return close_with_error(db, "Wrong password");
    }

    // Overwrite deleted content with zeros to prevent recovery of old records
    ZString secure_del_sql = "PRAGMA secure_delete=ON;";
    rc = db::sqlite3_exec(*db, secure_del_sql, null, null, &err_msg);
    if (rc != db::SQLITE_OK) {
        if (err_msg != null) {
            io::eprintf("Failed to enable secure_delete: %s\n", err_msg);
            db::sqlite3_free(err_msg);
        }
        // Non-fatal: continue even if this fails
    }

    return db::SQLITE_OK;
}

fn int create_vault(String master_pw, ZString filename) {
    db::Sqlite3 *db = null;

    int rc = open(master_pw, filename, &db);
    if (rc != db::SQLITE_OK) {
        return rc;
    }

    ZString sql = (ZString)
        "CREATE TABLE IF NOT EXISTS passwords ("
        "   site     TEXT NOT NULL,"
        "   username TEXT NOT NULL,"
        "   password TEXT NOT NULL,"
        "   PRIMARY KEY (site, username)"
        ");";

    db::Sqlite3Stmt *stmt = null;

    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        return close_with_error(&db, "Error preparing sql statement while creating table");
    }

    rc = db::sqlite3_step(stmt);

    int rc_finalize = db::sqlite3_finalize(stmt);

    db::sqlite3_close(db);

    if ( rc_finalize != db::SQLITE_OK) {
        io::eprintf("Error finalizing or executing statement while creating table");
        return rc;
    }

    return db::SQLITE_OK;
}

fn int ensure_master_registry(ZString filename) {
    db::Sqlite3 *db = null;

    int rc = open_plain(filename, &db);
    if (rc != db::SQLITE_OK) {
        return rc;
    }

    ZString sql = (ZString)
        "CREATE TABLE IF NOT EXISTS tracked_databases ("
        "   name       TEXT NOT NULL,"
        "   path       TEXT NOT NULL UNIQUE,"
        "   created_at INTEGER NOT NULL,"
        "   updated_at INTEGER NOT NULL"
        ");";

    db::Sqlite3Stmt *stmt = null;

    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        return close_with_error(&db, "Error preparing statement while creating registry");
    }

    rc = db::sqlite3_step(stmt);
    int rc_finalize = db::sqlite3_finalize(stmt);
    db::sqlite3_close(db);

    if (rc_finalize != db::SQLITE_OK) {
        io::eprintf("Error finalizing or executing statement while creating registry");
        return rc_finalize;
    }

    return db::SQLITE_OK;
}

fn int register_database(ZString master_db,
                         String db_name,
                         ZString db_path) {
    db::Sqlite3 *db = null;
    int rc = open_plain(master_db, &db);
    if (rc != db::SQLITE_OK) {
        return rc;
    }

    // Allow duplicate names at different paths - conflict is only checked
    // when using --db-name for lookup (not --db-path).
    ZString sql = (ZString)
        "INSERT INTO tracked_databases (name, path, created_at, updated_at) "
        "VALUES (?1, ?2, strftime('%s','now'), strftime('%s','now')) "
        "ON CONFLICT(path) DO UPDATE SET "
        "   name = excluded.name,"
        "   updated_at = excluded.updated_at;";

    db::Sqlite3Stmt *stmt = null;

    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        return close_with_error(&db, "Error preparing statement while registering database");
    }

    db::sqlite3_bind_text(stmt, 1, db_name.zstr_tcopy(), -1, null);
    db::sqlite3_bind_text(stmt, 2, db_path, -1, null);

    rc = db::sqlite3_step(stmt);
    int rc_finalize = db::sqlite3_finalize(stmt);
    db::sqlite3_close(db);

    if (rc != db::SQLITE_DONE || rc_finalize != db::SQLITE_OK) {
        io::eprintf("Error finalizing or executing statement while registering database");
        return rc;
    }

    return db::SQLITE_OK;
}

fn int name_distance(String a, String b) @local {
    int len_a = (int) a.len;
    int len_b = (int) b.len;
    int min_len = len_a < len_b ? len_a : len_b;
    int max_len = len_a > len_b ? len_a : len_b;
    int distance = max_len - min_len;

    for (int i = 0; i < min_len; i++) {
        if (a[i] != b[i]) {
            distance++;
        }
    }
    return distance;
}

fn DbPathMatches lookup_database_paths(ZString master_db,
                                 String db_name) {
    DbPathMatches matches = { .len = 0 };
    db::Sqlite3 *db = null;
    int rc = open_plain(master_db, &db);
    if (rc != db::SQLITE_OK) {
        return matches;
    }

    ZString sql = (ZString)
        "SELECT path FROM tracked_databases WHERE name = ?1 ORDER BY path ASC";
    db::Sqlite3Stmt *stmt = null;

    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        (void)close_with_error(&db, "Error preparing statement while loading tracked database");
        return matches;
    }

    db::sqlite3_bind_text(stmt, 1, db_name.zstr_tcopy(), -1, null);

    while ((rc = db::sqlite3_step(stmt)) == db::SQLITE_ROW) {
        if (matches.len >= MAX_DB_NUM) {
            io::eprintfn("Too many databases tracked with name '%s'; showing first %d.", db_name, MAX_DB_NUM);
            break;
        }
        String row_path = ((ZString) db::sqlite3_column_text(stmt, 0)).str_view();
        matches.paths[matches.len] = row_path.zstr_tcopy();
        matches.len++;
    }

    db::sqlite3_finalize(stmt);
    db::sqlite3_close(db);

    return matches;
}

fn ClosestDbMatch closest_database_match(ZString master_db,
                                         String target_name) {
    ClosestDbMatch closest = { .found = false, .name = "", .path = null, .distance = 0 };
    db::Sqlite3 *db = null;
    int rc = open_plain(master_db, &db);
    if (rc != db::SQLITE_OK) {
        return closest;
    }

    ZString sql = (ZString)
        "SELECT name, path FROM tracked_databases";
    db::Sqlite3Stmt *stmt = null;

    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        db::sqlite3_close(db);
        return closest;
    }

    while ((rc = db::sqlite3_step(stmt)) == db::SQLITE_ROW) {
        String candidate_name = ((ZString) db::sqlite3_column_text(stmt, 0)).str_view();
        int distance = name_distance(target_name, candidate_name);
        if (!closest.found || distance < closest.distance) {
            closest.found = true;
            closest.distance = distance;
            closest.name = candidate_name.tcopy();
            String candidate_path = ((ZString) db::sqlite3_column_text(stmt, 1)).str_view();
            closest.path = candidate_path.zstr_tcopy();
        }
    }

    int rc_finalize = db::sqlite3_finalize(stmt);
    db::sqlite3_close(db);

    if (rc_finalize != db::SQLITE_OK && closest.found) {
        io::eprintf("Error finalizing statement while loading tracked database");
    }

    return closest;
}

fn int prune_missing_databases(ZString master_db) {
    db::Sqlite3 *db = null;
    int rc = open_plain(master_db, &db);
    if (rc != db::SQLITE_OK) {
        return rc;
    }

    ZString sql = (ZString)
        "SELECT path FROM tracked_databases";
    db::Sqlite3Stmt *stmt = null;
    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        return close_with_error(&db, "Error preparing statement while pruning registry");
    }

    ZString del_sql = (ZString)
        "DELETE FROM tracked_databases WHERE path = ?1";
    db::Sqlite3Stmt *del_stmt = null;
    rc = db::sqlite3_prepare_v2(db, del_sql, -1, &del_stmt, null);
    if (rc != db::SQLITE_OK) {
        db::sqlite3_finalize(stmt);
        return close_with_error(&db, "Error preparing delete statement while pruning registry");
    }

    while ((rc = db::sqlite3_step(stmt)) == db::SQLITE_ROW) {
        String tracked_path = ((ZString) db::sqlite3_column_text(stmt, 0)).str_view();
        if (!path::exists(tracked_path.to_tpath())!!) {
            db::sqlite3_reset(del_stmt);
            db::sqlite3_clear_bindings(del_stmt);
            ZString tracked = tracked_path.zstr_tcopy();
            db::sqlite3_bind_text(del_stmt, 1, tracked, -1, null);
            db::sqlite3_step(del_stmt);
        }
    }

    if (rc != db::SQLITE_DONE) {
        db::sqlite3_finalize(stmt);
        db::sqlite3_finalize(del_stmt);
        db::sqlite3_close(db);
        return rc;
    }

    int rc_sel = db::sqlite3_finalize(stmt);
    int rc_del = db::sqlite3_finalize(del_stmt);
    db::sqlite3_close(db);

    if (rc_sel != db::SQLITE_OK || rc_del != db::SQLITE_OK) {
        io::eprintf("Error finalizing statements while pruning registry");
        return rc_sel != db::SQLITE_OK ? rc_sel : rc_del;
    }

    return db::SQLITE_OK;
}

fn void list_databases(ZString master_db) {
    db::Sqlite3 *db = null;
    int rc = open_plain(master_db, &db);
    if (rc != db::SQLITE_OK) {
        return;
    }

    ZString sql = (ZString)
        "SELECT name, path FROM tracked_databases ORDER BY name ASC";
    db::Sqlite3Stmt *stmt = null;

    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        db::sqlite3_close(db);
        return;
    }

    io::printf("Tracked databases:\n");
    while ((rc = db::sqlite3_step(stmt)) == db::SQLITE_ROW) {
        io::printf("  %s -> %s\n",
                   db::sqlite3_column_text(stmt, 0),
                   db::sqlite3_column_text(stmt, 1));
    }

    db::sqlite3_finalize(stmt);
    db::sqlite3_close(db);
}

fn int update_credentials(String master_pw,
                          ZString filename,
                          ZString site,
                          ZString acct,
                          String  spw) {
    // Use original String pointer with explicit length - no extra copy to avoid
    // leaving unwiped password data in memory. Caller is responsible for wiping spw.
    db::Sqlite3 *db = null;
    int rc = open(master_pw, filename, &db);
    if (rc != db::SQLITE_OK) {
        return rc;
    }

    ZString sql = (ZString)
        "INSERT INTO passwords (site, username, password)"
        "VALUES( ?1, ?2, ?3 )"
        "ON CONFLICT(site, username) DO UPDATE SET"
        "   username = excluded.username,"
        "   password = excluded.password;";

    db::Sqlite3Stmt *stmt = null;

    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        return close_with_error(&db, "Error preparing statement while modifying credentials");
    }

    db::sqlite3_bind_text(stmt, 1, site, -1, null);
    db::sqlite3_bind_text(stmt, 2, acct, -1, null);
    // Bind password with explicit length to avoid needing null-terminated copy
    db::sqlite3_bind_text(stmt, 3, (ZString)spw.ptr, (int)spw.len, null);

    rc = db::sqlite3_step(stmt);
    int rc_finalize = db::sqlite3_finalize(stmt);
    db::sqlite3_close(db);

    if (rc != db::SQLITE_DONE || rc_finalize != db::SQLITE_OK) {
        io::eprintf("Error finalizing or executing statement while modifying credentials");
        return rc;
    }

    return db::SQLITE_OK;
}

fn int remove_credentials(String master_pw,
                          ZString filename,
                          ZString site,
                          ZString acct) {
    db::Sqlite3 *db = null;
    int rc = open(master_pw, filename, &db);
    if (rc != db::SQLITE_OK) {
        return rc;
    }

    ZString sql = (ZString)
        "DELETE FROM passwords WHERE site == ?1 AND username == ?2";

    db::Sqlite3Stmt *stmt = null;

    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        return close_with_error(&db, "Error preparing statement while deleting credentials");
    }

    db::sqlite3_bind_text(stmt, 1, site, -1, null);
    db::sqlite3_bind_text(stmt, 2, acct, -1, null);

    rc = db::sqlite3_step(stmt);
    int rc_finalize = db::sqlite3_finalize(stmt);
    db::sqlite3_close(db);

    if (rc != db::SQLITE_DONE || rc_finalize != db::SQLITE_OK) {
        io::eprintf("Error finalizing or executing statement while deleting credentials");
        return rc;
    }

    return db::SQLITE_OK;
}

fn int return_credentials(String master_pw,
                          ZString filename,
                          ZString site) {
    db::Sqlite3 *db = null;
    int rc = open(master_pw, filename, &db);
    if (rc != db::SQLITE_OK) {
        return rc;
    }

    ZString sql = (ZString)
        "SELECT site, username FROM passwords WHERE site = ?1";
    db::Sqlite3Stmt *stmt = null;
    
    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        return close_with_error(&db, "Error preparing statement while retrieving credentials");
    }
    
    db::sqlite3_bind_text(stmt, 1, site, -1, null);

    rc = db::sqlite3_step(stmt);
    if (rc == db::SQLITE_DONE) {
        io::printf("No credentials found for site \'%s\'.\n");
    } else if (rc == db::SQLITE_ROW) {
        io::printf("This database has the credentials for the following accounts:\n");
        while (rc == db::SQLITE_ROW) {
            io::printf("%s\n", db::sqlite3_column_text(stmt, 0));
            rc = db::sqlite3_step(stmt);
        }
        if (rc != db::SQLITE_DONE) {
            return close_with_error(&db, "Error stepping while retrieving credentials");
        }
    } else {
            return close_with_error(&db, "Error stepping while retrieving credentials");
    }

    int rc_finalize = db::sqlite3_finalize(stmt);
    
    db::sqlite3_close(db);

    if (rc_finalize != db::SQLITE_OK) {
        io::eprintf("Error finalizing or executing statement while retrieving credentials");
        return rc;
    }

    return db::SQLITE_OK;
}



fn int return_credentials(String master_pw,
                          ZString filename,
                          ZString site,
                          ZString acct) {
    db::Sqlite3 *db = null;
    int rc = open(master_pw, filename, &db);
    if (rc != db::SQLITE_OK) {
        return rc;
    }

    ZString sql = (ZString)
        "SELECT site, username, password FROM passwords WHERE site = ?1 AND username = ?2";
    db::Sqlite3Stmt *stmt = null;

    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        return close_with_error(&db, "Error preparing statement while retrieving credentials");
    }

    db::sqlite3_bind_text(stmt, 1, site, -1, null);
    db::sqlite3_bind_text(stmt, 2, acct, -1, null);

    rc = db::sqlite3_step(stmt);
    if (rc == db::SQLITE_ROW) {
        io::printf("Site: %s\n"
                   "User: %s\n"
                   "Password copied to clipboard.\n",
                   db::sqlite3_column_text(stmt, 0),
                   db::sqlite3_column_text(stmt, 1));
        secure::output_pw(db::sqlite3_column_text(stmt, 2).str_view());
        rc = db::SQLITE_OK;
    }
    
    int rc_finalize = db::sqlite3_finalize(stmt);
    
    db::sqlite3_close(db);

    if (rc_finalize != db::SQLITE_OK) {
        io::eprintf("Error finalizing or executing statement while retrieving credentials");
        return rc;
    }

    return db::SQLITE_OK;
}
