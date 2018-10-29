type t

val make : Path.t -> string -> t
val placeAt : Path.t -> t -> unit RunAsync.t
