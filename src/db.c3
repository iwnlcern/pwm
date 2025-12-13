module db;

import std::core; // for String, ZString, etc.

// Opaque handles – mapped to C's `struct sqlite3` and `struct sqlite3_stmt`.
struct Sqlite3      @cname("sqlite3") { char _unused; }
struct Sqlite3Stmt  @cname("sqlite3_stmt") { char _unused; }

// Error & step codes you care about.
const int SQLITE_OK  = 0;
const int SQLITE_ROW = 100;
const int SQLITE_DONE = 101;

// Core functions (C signatures copied from sqlite3.h)
extern fn int sqlite3_open(ZString filename, Sqlite3** db);
extern fn int sqlite3_close(Sqlite3* db);

extern fn int sqlite3_exec(
    Sqlite3* db,
    ZString sql,
    void* callback,   // usually null
    void* arg,
    char** errmsg
);

extern fn int sqlite3_prepare_v2(
    Sqlite3* db,
    ZString sql,
    int nByte,
    Sqlite3Stmt** stmt,
    ZString* tail // can be null
);

extern fn int sqlite3_step(Sqlite3Stmt* stmt);
extern fn int sqlite3_finalize(Sqlite3Stmt* stmt);

extern fn int sqlite3_bind_text(
    Sqlite3Stmt* stmt,
    int index,
    ZString value,
    int n,
    void* destructor // pass null for SQLITE_TRANSIENT-ish semantics if you keep it alive
);

extern fn int sqlite3_bind_int64(Sqlite3Stmt* stmt, long value);

extern fn ZString sqlite3_errmsg(Sqlite3* db);
extern fn ZString sqlite3_column_text(Sqlite3Stmt* stmt, int iCol);
extern fn long    sqlite3_column_int64(Sqlite3Stmt* stmt, int iCol);
extern fn void    sqlite3_free(void* b);
