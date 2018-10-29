type t

val readOfPath : prefixPath:Path.t -> filePath:Path.t -> t RunAsync.t
val writeToDir : destinationDir:Path.t -> t -> unit RunAsync.t

include S.COMPARABLE with type t := t
include S.JSONABLE with type t := t
