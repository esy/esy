type t

val make : Path.t -> string -> t

val ofDir : Path.t -> t list RunAsync.t
val placeAt : Path.t -> t -> unit RunAsync.t
