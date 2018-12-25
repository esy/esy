type t

val empty : t
val add : string -> Resolution.resolution -> t -> t
val find : t -> string -> Resolution.t option

val entries : t -> Resolution.t list

val to_yojson : t Json.encoder
val of_yojson : t Json.decoder

val digest : t -> Digestv.t
