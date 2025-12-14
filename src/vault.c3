module pwm::vault;
import std::io;
import db;
import libc;

import misc::secure;

extern fn int sqlite3_key(db::Sqlite3 *db, void *key, int key_len);

fn void close_with_error(db::Sqlite3 *db, String msg) @local {
    io::eprintf("%s: %s\n", msg, db::sqlite3_errmsg(db));
    db::sqlite3_close(db);
    libc::exit(1);
}

fn int open(String master_pw,
            ZString filename,
            db::Sqlite3 **db) @local {

    int rc = db::sqlite3_open(filename, db);

    if (rc) {
        io::eprintf("Can't open database: %s\n", db::sqlite3_errmsg(*db));
        return rc;
    }

    void *key_ptr = master_pw.ptr;
    int key_len = (int) master_pw.len;

    rc = sqlite3_key(*db, key_ptr, key_len);

    ZString check_sql = "PRAGMA cipher_integrity_check;";
    ZString err_msg = null;

    rc = db::sqlite3_exec(*db, check_sql, null, null, &err_msg);
    if (rc != db::SQLITE_OK) {
        if (err_msg != null) {
            io::eprintf("Wrong password or corrupt DB: %s\n", err_msg);
            db::sqlite3_free(err_msg);
        }
        close_with_error(*db, "Wrong password");
    }
    return rc;
}

fn int create_vault(String master_pw, ZString filename) {
    db::Sqlite3 *db = null;

    int rc = open(master_pw, filename, &db);

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
        close_with_error(db, "Error preparing sql statement while creating table");
        return rc;
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

fn int update_credentials(String master_pw,
                          ZString filename,
                          ZString site,
                          ZString acct,
                          String  spw) {
    ZString pw = (ZString) spw;
    db::Sqlite3 *db;
    int rc = open(master_pw, filename, &db);
    ZString sql = (ZString)
        "INSERT INTO passwords (site, username, password)"
        "VALUES( ?1, ?2, ?3 )"
        "ON CONFLICT(site, username) DO UPDATE SET"
        "   username = excluded.username,"
        "   password = excluded.password;";

    db::Sqlite3Stmt *stmt = null;

    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        close_with_error(db, "Error preparing statement while modifying credentials");
        return rc;
    }

    db::sqlite3_bind_text(stmt, 1, site, -1, null);
    db::sqlite3_bind_text(stmt, 2, acct, -1, null);
    db::sqlite3_bind_text(stmt, 3, pw, -1, null);

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
    db::Sqlite3 *db;
    int rc = open(master_pw, filename, &db);
    ZString sql = (ZString)
        "DELETE FROM passwords WHERE site == ?1 AND username == ?2";

    db::Sqlite3Stmt *stmt = null;
    
    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        close_with_error(db, "Error preparing statement while deleting credentials");
        return rc;
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
                          ZString site,
                          ZString acct) {
    db::Sqlite3 *db;
    int rc = open(master_pw, filename, &db);
    ZString sql = (ZString)
        "SELECT site, username, password FROM passwords WHERE site = ?1 AND username = ?2";
    db::Sqlite3Stmt *stmt;

    rc = db::sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != db::SQLITE_OK) {
        close_with_error(db, "Error preparing statement while retrieving credentials");
        return rc;
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
