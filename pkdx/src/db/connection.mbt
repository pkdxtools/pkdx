/// Convert a MoonBit String to null-terminated UTF-8 Bytes for C FFI.
pub fn to_c_bytes(s : String) -> Bytes {
  pkdx_string_to_utf8(s, s.length())
}

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

/// Close a database connection.
pub fn close(db : Db) -> Unit {
  pkdx_db_close(db)
}

/// Execute a query with string bind parameters.
pub fn query(
  db : Db,
  sql : String,
  binds : Array[String]
) -> Result[Array[Array[String]], String] {
  let sql_bytes = to_c_bytes(sql)
  let bind_count = binds.length()
  let bind_bytes : FixedArray[Bytes] = FixedArray::make(bind_count, Bytes::make(1, 0))
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

/// Check if a required table exists in the database.
pub fn table_exists(db : Db, table_name : String) -> Bool {
  pkdx_table_exists(db, to_c_bytes(table_name)) > 0
}

/// Validate that all required tables exist.
pub fn validate_schema(db : Db) -> Result[Unit, String] {
  let required = [
    "pokedex_name", "local_pokedex_type", "local_pokedex_status",
    "local_pokedex_ability", "local_waza", "local_waza_language",
  ]
  let missing : Array[String] = []
  for i = 0; i < required.length(); i = i + 1 {
    if not(table_exists(db, required[i])) {
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
