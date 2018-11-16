type t

val checksum : t -> Checksum.t RunAsync.t

val ofDir : Path.t -> t list RunAsync.t
val placeAt : Path.t -> t -> unit RunAsync.t
