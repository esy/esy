
val readFile : Path.t -> string RunAsync.t

val readJsonFile : Path.t -> Yojson.Safe.json RunAsync.t

val exists : Path.t -> bool RunAsync.t

val withTemporaryFile : (Path.t -> Lwt_io.output_channel -> 'a Lwt.t) -> 'a Lwt.t
