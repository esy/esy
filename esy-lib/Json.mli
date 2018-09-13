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
  val string : t -> (string, string) result
  val assoc : t -> ((string * t) list, string) result
  val field : name:string -> t -> (t, string) result
  val fieldOpt : name:string -> t -> (t option, string) result
  val fieldWith :
    name:string -> (t -> ('a, string) result) -> t -> ('a, string) result
  val fieldOptWith :
    name:string ->
    (t -> ('a option, string) result) -> t -> ('a option, string) result
  val list :
    ?errorMsg:string ->
    (t -> ('a, string) result) -> t -> ('a list, string) result
  val stringMap :
    ?errorMsg:string ->
    (t -> ('a, string) result) -> t -> ('a StringMap.t, string) result
  val cmd : ?errorMsg:string -> t -> (Cmd.t, string) result
end
