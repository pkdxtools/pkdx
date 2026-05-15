///|
extern "C" fn pkdx_read_stdin() -> String = "pkdx_read_stdin"

///|
#borrow(path, content)
extern "C" fn pkdx_write_file(path : Bytes, content : Bytes) -> Int = "pkdx_write_file"

///|
extern "C" fn pkdx_exit(code : Int) -> Unit = "pkdx_exit"

///|
#borrow(msg)
extern "C" fn pkdx_eprintln(msg : Bytes) -> Unit = "pkdx_eprintln"

///|
extern "C" fn pkdx_monotonic_ns() -> Int64 = "pkdx_monotonic_ns"

///|
extern "C" fn pkdx_pid() -> Int = "pkdx_pid"
