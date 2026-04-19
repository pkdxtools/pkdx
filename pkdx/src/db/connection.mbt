///|
/// Convert a MoonBit String to null-terminated UTF-8 Bytes for C FFI.
pub fn to_c_bytes(s : String) -> Bytes {
  pkdx_string_to_utf8(s, s.length())
}

///|
/// Open a database connection, returning Result.
pub fn open(path : String) -> Result[Db, String] {
  let path_bytes = to_c_bytes(path)
  let out : FixedArray[Db] = FixedArray::make(1, pkdx_null_db())
  let rc = pkdx_db_open(path_bytes, out)
  if rc == 0 {
    Ok(out[0])
  } else {
    Err("Failed to open database: " + path)
  }
}

///|
/// Open for read-write. Used by `pkdx migrate`. The file must already
/// exist — we deliberately omit SQLITE_OPEN_CREATE so a missing DB is
/// surfaced as an error instead of silently creating an empty one.
pub fn open_rw(path : String) -> Result[Db, String] {
  let path_bytes = to_c_bytes(path)
  let out : FixedArray[Db] = FixedArray::make(1, pkdx_null_db())
  let rc = pkdx_db_open_rw(path_bytes, out)
  if rc == 0 {
    Ok(out[0])
  } else {
    Err("Failed to open database (rw): " + path)
  }
}

///|
/// Close a database connection.
pub fn close(db : Db) -> Unit {
  pkdx_db_close(db)
}

///|
/// Tagged bind value. SQLite's type affinity would accept TEXT for
/// everything, but migration SQL relies on NULL-vs-"" distinctions
/// (COALESCE fallbacks in 001/002), so we model NULL explicitly.
/// Variant names are prefixed `Bind` to avoid colliding with the Int
/// built-in type when used in downstream packages.
pub(all) enum BindValue {
  BindNull
  BindText(String)
  BindInt(Int)
}

///|
/// Normalize "" → BindNull. Matches Ruby's
/// `entry['x'].to_s == '' ? nil : entry['x']` idiom.
pub fn text_or_null(s : String) -> BindValue {
  if s.length() == 0 {
    BindNull
  } else {
    BindText(s)
  }
}

///|
/// Execute a non-query SQL statement (DDL, BEGIN/COMMIT, etc.).
pub fn exec(db : Db, sql : String) -> Result[Unit, String] {
  let rc = pkdx_exec_sql(db, to_c_bytes(sql))
  if rc == 0 {
    Ok(())
  } else {
    Err("exec failed (rc=" + rc.to_string() + "): " + sql)
  }
}

///|
/// Execute a parameterised non-query statement (UPDATE / INSERT / DELETE
/// with binds). Rows are consumed and discarded.
pub fn exec_binds(
  db : Db,
  sql : String,
  binds : Array[BindValue],
) -> Result[Unit, String] {
  match query_binds_impl(db, sql, binds) {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
}

///|
/// Execute a parameterised query and return nullable cells.
pub fn query_binds(
  db : Db,
  sql : String,
  binds : Array[BindValue],
) -> Result[Array[Array[String?]], String] {
  query_binds_impl(db, sql, binds)
}

///|
fn query_binds_impl(
  db : Db,
  sql : String,
  binds : Array[BindValue],
) -> Result[Array[Array[String?]], String] {
  let sql_bytes = to_c_bytes(sql)
  let n = binds.length()
  let tags : FixedArray[Int] = FixedArray::make(if n == 0 { 1 } else { n }, 0)
  let bind_bytes : FixedArray[Bytes] = FixedArray::make(
    if n == 0 { 1 } else { n },
    Bytes::make(1, 0),
  )
  for i = 0; i < n; i = i + 1 {
    match binds[i] {
      BindNull => {
        tags[i] = 0
        bind_bytes[i] = Bytes::make(1, 0)
      }
      BindText(s) => {
        tags[i] = 1
        bind_bytes[i] = to_c_bytes(s)
      }
      BindInt(v) => {
        tags[i] = 2
        bind_bytes[i] = to_c_bytes(v.to_string())
      }
    }
  }
  let out : FixedArray[ResultSet] = FixedArray::make(1, pkdx_null_rs())
  let rc = pkdx_exec_query_typed(db, sql_bytes, n, tags, bind_bytes, out)
  if rc != 0 {
    return Err("query failed (rc=" + rc.to_string() + "): " + sql)
  }
  let rs = out[0]
  let row_count = pkdx_result_row_count(rs)
  let col_count = pkdx_result_col_count(rs)
  let rows : Array[Array[String?]] = []
  for r = 0; r < row_count; r = r + 1 {
    let row : Array[String?] = []
    for c = 0; c < col_count; c = c + 1 {
      if pkdx_result_is_null(rs, r, c) != 0 {
        row.push(None)
      } else {
        row.push(Some(pkdx_result_get(rs, r, c)))
      }
    }
    rows.push(row)
  }
  pkdx_result_free(rs)
  Ok(rows)
}

///|
/// Rows modified by the last INSERT/UPDATE/DELETE on this connection.
pub fn changes(db : Db) -> Int {
  pkdx_db_changes(db)
}

///|
/// Read a UTF-8 file. Returns None if missing or empty.
pub fn read_file(path : String) -> String? {
  if pkdx_file_exists(to_c_bytes(path)) == 0 {
    None
  } else {
    Some(pkdx_read_file(to_c_bytes(path)))
  }
}

///|
pub fn file_exists(path : String) -> Bool {
  pkdx_file_exists(to_c_bytes(path)) != 0
}

///|
/// Print a progress line, flushing immediately.
pub fn println_progress(msg : String) -> Unit {
  pkdx_println_bytes(to_c_bytes(msg))
}

///|
/// Execute a query with string bind parameters.
pub fn query(
  db : Db,
  sql : String,
  binds : Array[String],
) -> Result[Array[Array[String]], String] {
  let sql_bytes = to_c_bytes(sql)
  let bind_count = binds.length()
  let bind_bytes : FixedArray[Bytes] = FixedArray::make(
    bind_count,
    Bytes::make(1, 0),
  )
  for i = 0; i < bind_count; i = i + 1 {
    bind_bytes[i] = to_c_bytes(binds[i])
  }
  let out : FixedArray[ResultSet] = FixedArray::make(1, pkdx_null_rs())
  let rc = pkdx_exec_query(db, sql_bytes, bind_count, bind_bytes, out)
  if rc != 0 {
    return Err("Query execution failed")
  }
  let rs = out[0]
  let row_count = pkdx_result_row_count(rs)
  let col_count = pkdx_result_col_count(rs)
  let rows : Array[Array[String]] = []
  for r = 0; r < row_count; r = r + 1 {
    let row : Array[String] = []
    for c = 0; c < col_count; c = c + 1 {
      row.push(pkdx_result_get(rs, r, c))
    }
    rows.push(row)
  }
  pkdx_result_free(rs)
  Ok(rows)
}

///|
/// Check if a required table exists in the database.
pub fn table_exists(db : Db, table_name : String) -> Bool {
  pkdx_table_exists(db, to_c_bytes(table_name)) > 0
}

///|
/// Validate that all required tables exist.
pub fn validate_schema(db : Db) -> Result[Unit, String] {
  let required = [
    "pokedex_name", "local_pokedex_type", "local_pokedex_status", "local_pokedex_ability",
    "local_waza", "local_waza_language",
  ]
  let missing : Array[String] = []
  for i = 0; i < required.length(); i = i + 1 {
    if !table_exists(db, required[i]) {
      missing.push(required[i])
    }
  }
  if missing.length() > 0 {
    let mut msg = "Missing required tables: "
    for i = 0; i < missing.length(); i = i + 1 {
      if i > 0 {
        msg = msg + ", "
      }
      msg = msg + missing[i]
    }
    Err(msg)
  } else {
    Ok(())
  }
}
