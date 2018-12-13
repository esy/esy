type t

val digest : t -> Digestv.t RunAsync.t

val ofDir : Path.t -> t list RunAsync.t
val placeAt : Path.t -> t -> unit RunAsync.t
