///|
/// Opaque external types for SQLite resources
pub type Db

///|
pub type ResultSet

///|
/// Convert MoonBit String (UTF-16) to null-terminated UTF-8 Bytes via C.
#borrow(s)
extern "C" fn pkdx_string_to_utf8(s : String, len : Int) -> Bytes = "pkdx_string_to_utf8"

///|
/// Create a null/placeholder Db for FixedArray init.
extern "C" fn pkdx_null_db() -> Db = "pkdx_null_db"

///|
/// Open a SQLite database in read-only mode.
/// Returns error code: 0 = success, non-zero = failure.
#borrow(path, out)
extern "C" fn pkdx_db_open(path : Bytes, out : FixedArray[Db]) -> Int = "pkdx_db_open"

///|
/// Open a SQLite database in read-write mode. The file must exist —
/// migrations assume pokedex submodule has already created it.
#borrow(path, out)
extern "C" fn pkdx_db_open_rw(
  path : Bytes,
  out : FixedArray[Db],
) -> Int = "pkdx_db_open_rw"

///|
/// Close an open database connection.
#borrow(db)
extern "C" fn pkdx_db_close(db : Db) -> Unit = "pkdx_db_close"

///|
/// Execute a SQL statement that returns no rows (DDL, BEGIN/COMMIT, etc.).
#borrow(db, sql)
extern "C" fn pkdx_exec_sql(db : Db, sql : Bytes) -> Int = "pkdx_exec_sql"

///|
/// Number of rows modified by the most recent INSERT/UPDATE/DELETE.
#borrow(db)
extern "C" fn pkdx_db_changes(db : Db) -> Int = "pkdx_db_changes"

///|
/// Execute a SQL query with bound parameters.
/// Returns error code: 0 = success.
#borrow(db, sql, bind_values, out)
extern "C" fn pkdx_exec_query(
  db : Db,
  sql : Bytes,
  bind_count : Int,
  bind_values : FixedArray[Bytes],
  out : FixedArray[ResultSet],
) -> Int = "pkdx_exec_query"

///|
/// Execute a query with type-tagged binds. tags[i]: 0 = NULL, 1 = TEXT,
/// 2 = INTEGER (values[i] is ASCII decimal string).
#borrow(db, sql, tags, bind_values, out)
extern "C" fn pkdx_exec_query_typed(
  db : Db,
  sql : Bytes,
  bind_count : Int,
  tags : FixedArray[Int],
  bind_values : FixedArray[Bytes],
  out : FixedArray[ResultSet],
) -> Int = "pkdx_exec_query_typed"

///|
/// Whether cell (row, col) was NULL in the source row (1 = NULL, 0 = not).
#borrow(rs)
extern "C" fn pkdx_result_is_null(
  rs : ResultSet,
  row : Int,
  col : Int,
) -> Int = "pkdx_result_is_null"

///|
/// Create a null/placeholder ResultSet for FixedArray init.
extern "C" fn pkdx_null_rs() -> ResultSet = "pkdx_null_rs"

///|
/// Get the number of rows in a result set.
#borrow(rs)
extern "C" fn pkdx_result_row_count(rs : ResultSet) -> Int = "pkdx_result_row_count"

///|
/// Get the number of columns in a result set.
#borrow(rs)
extern "C" fn pkdx_result_col_count(rs : ResultSet) -> Int = "pkdx_result_col_count"

///|
/// Get a cell value as a String (UTF-16, converted from UTF-8 in C).
#borrow(rs)
extern "C" fn pkdx_result_get(rs : ResultSet, row : Int, col : Int) -> String = "pkdx_result_get"

///|
/// Free a result set and all its owned strings.
#borrow(rs)
extern "C" fn pkdx_result_free(rs : ResultSet) -> Unit = "pkdx_result_free"

///|
/// Check if a table exists in the database.
#borrow(db, table_name)
extern "C" fn pkdx_table_exists(db : Db, table_name : Bytes) -> Int = "pkdx_table_exists"

///|
/// Read the entire file at `path` as a UTF-8 string (up to 8 MiB).
/// Returns an empty string on error — callers must distinguish via
/// `file_exists` or a non-empty-size precondition.
#borrow(path)
extern "C" fn pkdx_read_file(path : Bytes) -> String = "pkdx_read_file"

///|
#borrow(path)
extern "C" fn pkdx_file_exists(path : Bytes) -> Int = "pkdx_file_exists"

///|
/// Print to stdout with a trailing newline. Flushes immediately so
/// progress messages from migrations surface before the next step.
#borrow(msg)
extern "C" fn pkdx_println_bytes(msg : Bytes) -> Unit = "pkdx_println"
