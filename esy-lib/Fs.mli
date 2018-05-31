
val readFile : Path.t -> string RunAsync.t

val writeFile : data:string -> Path.t -> unit RunAsync.t

val readJsonFile : Path.t -> Yojson.Safe.json RunAsync.t

val writeJsonFile : json:Yojson.Safe.json -> Path.t -> unit RunAsync.t

val openFile : mode:Lwt_unix.open_flag list -> perm:int -> Path.t -> Lwt_unix.file_descr RunAsync.t

val exists : Path.t -> bool RunAsync.t

(** Check if the path exists and is a directory *)
val isDir : Path.t -> bool RunAsync.t

val unlink : Path.t -> unit RunAsync.t

val readlink : Path.t -> Path.t RunAsync.t
val symlink : source:Path.t -> Path.t -> unit RunAsync.t
val rename : source:Path.t -> Path.t -> unit RunAsync.t

val realpath : Path.t -> Path.t RunAsync.t

val stat : Path.t -> Unix.stats RunAsync.t

(** List directory and return a list of names excluding . and .. *)
val listDir : Path.t -> string list RunAsync.t

val createDirectory : Path.t -> unit RunAsync.t

val chmod : int -> Path.t -> unit RunAsync.t

val fold :
  ?skipTraverse : (Path.t -> bool)
  -> f : ('a -> Path.t -> Unix.stats -> 'a Lwt.t)
  -> init : 'a
  -> Path.t
  -> 'a Lwt.t

val traverse :
  ?skipTraverse : (Path.t -> bool)
  -> f : (Path.t -> Lwt_unix.stats -> unit RunAsync.t)
  -> Path.t
  -> unit RunAsync.t

val copyFile : origPath:Path.t -> destPath:Path.t -> unit RunAsync.t
val copyPath : origPath:Path.t -> destPath:Path.t -> unit RunAsync.t

val rmPath : Path.t -> [`Removed | `NoSuchPath] RunAsync.t

val withTempDir : ?tempDir:string -> (Path.t -> 'a Lwt.t) -> 'a Lwt.t
val withTempFile : string -> (Path.t -> 'a Lwt.t) -> 'a Lwt.t
