module db;

struct Sqlite3      @cname("sqlite3") { char _unused; }
struct Sqlite3Stmt  @cname("sqlite3_stmt") { char _unused; }

const int SQLITE_OK         =  0;   /* Successful result */
/* beginning of error codes */
const int SQLITE_ERROR      =  1;   /* SQL Error or missing database */
const int SQLITE_INTERNAL   =  2;   /* Internal logic error in SQLite */
const int SQLITE_PERM       =  3;   /* Access permission denied */
const int SQLITE_ABORT      =  4;   /* Callback routine requested an abort */
const int SQLITE_BUSY       =  5;   /* The database file is locked */
const int SQLITE_LOCKED     =  6;   /* A table in the database is locked */
const int SQLITE_NOMEM      =  7;   /* A malloc() failed */
const int SQLITE_READONLY   =  8;   /* Attempt to write a readonly database */
const int SQLITE_INTERRUPT  =  9;   /* Operation terminated by interrupt() */
const int SQLITE_IOERR      = 10;   /* Some kind of disk I/O error occurred */
const int SQLITE_CORRUPT    = 11;   /* The database disk image is malformed */
const int SQLITE_NOTFOUND   = 12;   /* Unknown opcode in file_control() */
const int SQLITE_FULL       = 13;   /* Insertion failed because database is full */
const int SQLITE_CANTOPEN   = 14;   /* Unable to open the database file */
const int SQLITE_PROTOCOL   = 15;   /* Database lock protocol error */
const int SQLITE_EMPTY      = 16;   /* Internal use only */
const int SQLITE_SCHEMA     = 17;   /* The database schema changed */
const int SQLITE_TOOBIG     = 18;   /* String or BLOB exceeds size limit */
const int SQLITE_CONSTRAINT = 19;   /* Abort due to constraint violation */
const int SQLITE_MISMATCH   = 20;   /* Data type mismatch */
const int SQLITE_MISUSE     = 21;   /* Library used incorrectly */
const int SQLITE_NOLFS      = 22;   /* Uses OS features not supported on host */
const int SQLITE_AUTH       = 23;   /* Authorization denied */
const int SQLITE_FORMAT     = 24;   /* Not used */
const int SQLITE_RANGE      = 25;   /* 2nd parameter to bind out of range */
const int SQLITE_NOTADB     = 26;   /* File opened that is not a database file */
const int SQLITE_NOTICE     = 27;   /* Notifications from log() */
const int SQLITE_WARNING    = 28;   /* Warnings from log() */
const int SQLITE_ROW        = 100;  /* sqlite3_step() has another row ready */
const int SQLITE_DONE       = 101;  /* sqlite3_step() has finished executing */

extern fn int sqlite3_open(ZString filename, Sqlite3** db);
extern fn int sqlite3_close(Sqlite3* db);

extern fn int sqlite3_exec(
    Sqlite3* db,
    ZString sql,
    void* callback,
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
extern fn int sqlite3_reset(Sqlite3Stmt* stmt);
extern fn int sqlite3_clear_bindings(Sqlite3Stmt* stmt);

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
