type part

val part_to_yojson : part Json.encoder
val part_of_yojson : part Json.decoder

type t

include S.COMPARABLE with type t := t

val ofFile : Path.t -> t RunAsync.t
val ofString : string -> t
val ofJson : Json.t -> t

val empty : t

val string : string -> part
val json : Json.t -> part

val add : part -> t -> t

val combine : t -> t -> t
val (+) : t -> t -> t

val toHex : t -> string
