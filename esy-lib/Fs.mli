(**
 * Async filesystem API.
 *)

val readFile : Path.t -> string RunAsync.t

val writeFile : ?perm:int -> data:string -> Path.t -> unit RunAsync.t

val readJsonFile : Path.t -> Yojson.Safe.json RunAsync.t

val writeJsonFile : json:Yojson.Safe.json -> Path.t -> unit RunAsync.t

val openFile : mode:Lwt_unix.open_flag list -> perm:int -> Path.t -> Lwt_unix.file_descr RunAsync.t

(** Check if the path exists *)
val exists : Path.t -> bool RunAsync.t

(** Check if the path exists and is a directory *)
val isDir : Path.t -> bool RunAsync.t

(** Check if directory is empty **)
val isEmpty: Path.t -> bool

val unlink : Path.t -> unit RunAsync.t

(** readlink *)
val readlink : Path.t -> Path.t RunAsync.t

(** Link readlink but returns [None] if path doesn't not exist. *)
val readlinkOpt : Path.t -> Path.t option RunAsync.t

val symlink : ?force:bool -> src:Path.t -> Path.t -> unit RunAsync.t
val rename : src:Path.t -> Path.t -> unit RunAsync.t

val realpath : Path.t -> Path.t RunAsync.t

val stat : Path.t -> Unix.stats RunAsync.t

(** List directory and return a list of names excluding . and .. *)
val listDir : Path.t -> string list RunAsync.t

val createDir : Path.t -> unit RunAsync.t

val chmod : int -> Path.t -> unit RunAsync.t

val fold :
  ?skipTraverse : (Path.t -> bool)
  -> f : ('a -> Path.t -> Unix.stats -> 'a RunAsync.t)
  -> init : 'a
  -> Path.t
  -> 'a RunAsync.t

val traverse :
  ?skipTraverse : (Path.t -> bool)
  -> f : (Path.t -> Lwt_unix.stats -> unit RunAsync.t)
  -> Path.t
  -> unit RunAsync.t

val copyFile : src:Path.t -> dst:Path.t -> unit RunAsync.t
val copyPath : src:Path.t -> dst:Path.t -> unit RunAsync.t

val rmPath : Path.t -> unit RunAsync.t
val rmPathLwt : Path.t -> unit Lwt.t

val withTempDir : ?tempDir:string -> (Path.t -> 'a Lwt.t) -> 'a Lwt.t
val withTempFile : data:string -> (Path.t -> 'a Lwt.t) -> 'a Lwt.t
