/// Opaque external types for SQLite resources
pub type Db

pub type ResultSet

/// Convert MoonBit String (UTF-16) to null-terminated UTF-8 Bytes via C.
#borrow(s)
extern "C" fn pkdx_string_to_utf8(s : String, len : Int) -> Bytes = "pkdx_string_to_utf8"

/// Create a null/placeholder Db for FixedArray init.
extern "C" fn pkdx_null_db() -> Db = "pkdx_null_db"

/// Open a SQLite database in read-only mode.
/// Returns error code: 0 = success, non-zero = failure.
#borrow(path, out)
extern "C" fn pkdx_db_open(path : Bytes, out : FixedArray[Db]) -> Int = "pkdx_db_open"

/// Close an open database connection.
#borrow(db)
extern "C" fn pkdx_db_close(db : Db) -> Unit = "pkdx_db_close"

/// Execute a SQL query with bound parameters.
/// Returns error code: 0 = success.
#borrow(db, sql, bind_values, out)
extern "C" fn pkdx_exec_query(
  db : Db,
  sql : Bytes,
  bind_count : Int,
  bind_values : FixedArray[Bytes],
  out : FixedArray[ResultSet]
) -> Int = "pkdx_exec_query"

/// Create a null/placeholder ResultSet for FixedArray init.
extern "C" fn pkdx_null_rs() -> ResultSet = "pkdx_null_rs"

/// Get the number of rows in a result set.
#borrow(rs)
extern "C" fn pkdx_result_row_count(rs : ResultSet) -> Int = "pkdx_result_row_count"

/// Get the number of columns in a result set.
#borrow(rs)
extern "C" fn pkdx_result_col_count(rs : ResultSet) -> Int = "pkdx_result_col_count"

/// Get a cell value as a String (UTF-16, converted from UTF-8 in C).
#borrow(rs)
extern "C" fn pkdx_result_get(
  rs : ResultSet,
  row : Int,
  col : Int
) -> String = "pkdx_result_get"

/// Free a result set and all its owned strings.
#borrow(rs)
extern "C" fn pkdx_result_free(rs : ResultSet) -> Unit = "pkdx_result_free"

/// Check if a table exists in the database.
#borrow(db, table_name)
extern "C" fn pkdx_table_exists(db : Db, table_name : Bytes) -> Int = "pkdx_table_exists"
