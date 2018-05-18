
val readFile : EsyLib.Path.t -> string RunAsync.t

val readJsonFile : EsyLib.Path.t -> Yojson.Safe.json RunAsync.t

val openFile : mode:Lwt_unix.open_flag list -> perm:int -> EsyLib.Path.t -> Lwt_unix.file_descr RunAsync.t

val exists : EsyLib.Path.t -> bool RunAsync.t

val unlink : EsyLib.Path.t -> unit RunAsync.t

val readlink : EsyLib.Path.t -> EsyLib.Path.t RunAsync.t
val symlink : source:EsyLib.Path.t -> EsyLib.Path.t -> unit RunAsync.t
val rename : source:EsyLib.Path.t -> EsyLib.Path.t -> unit RunAsync.t

val realpath : EsyLib.Path.t -> EsyLib.Path.t RunAsync.t

val stat : EsyLib.Path.t -> Unix.stats RunAsync.t

val createDirectory : EsyLib.Path.t -> unit RunAsync.t

val chmod : int -> EsyLib.Path.t -> unit RunAsync.t

val fold :
  ?skipTraverse : (EsyLib.Path.t -> bool)
  -> f : ('a -> EsyLib.Path.t -> Unix.stats -> 'a Lwt.t)
  -> init : 'a
  -> EsyLib.Path.t
  -> 'a Lwt.t

val traverse :
  ?skipTraverse : (EsyLib.Path.t -> bool)
  -> f : (EsyLib.Path.t -> Lwt_unix.stats -> unit RunAsync.t)
  -> EsyLib.Path.t
  -> unit RunAsync.t

val copyFile : origPath:EsyLib.Path.t -> destPath:EsyLib.Path.t -> unit RunAsync.t
val copyPath : origPath:EsyLib.Path.t -> destPath:EsyLib.Path.t -> unit RunAsync.t

val rmPath : EsyLib.Path.t -> [`Removed | `NoSuchPath] RunAsync.t

val withTempDir : ?tempDir:string -> (EsyLib.Path.t -> 'a Lwt.t) -> 'a Lwt.t
val withTempFile : string -> (EsyLib.Path.t -> 'a Lwt.t) -> 'a Lwt.t
