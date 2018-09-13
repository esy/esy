type t = Yojson.Safe.json

type 'a encoder = 'a -> t
type 'a decoder = t -> ('a, string) result

val to_yojson : t encoder
val of_yojson : t decoder

val pp : ?std:bool -> Format.formatter -> t -> unit

val mergeAssoc : (string * t) list -> (string * t) list -> (string * t) list

val parseJsonWith : ('a -> ('b, string) result) -> 'a -> 'b Run.t
val parseStringWith : (t -> ('b, string) result) -> string -> ('b, Run.error) result

module Decode : sig

  val string : string decoder
  val assoc :(string * t) list decoder
  val field : name:string -> t decoder
  val fieldOpt : name:string -> t option decoder
  val fieldWith : name:string -> 'a decoder -> 'a decoder
  val fieldOptWith : name:string -> 'a option decoder -> 'a option decoder
  val list : ?errorMsg:string -> 'a decoder -> 'a list decoder
  val stringMap : ?errorMsg:string -> 'a decoder -> 'a StringMap.t decoder
end
