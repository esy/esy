type t = Yojson.Safe.json

type 'a encoder = 'a -> t
type 'a decoder = t -> ('a, string) result

val to_yojson : t -> t
val of_yojson : t -> (t, string) result

val compare : t -> t -> int

val show : ?std:bool -> t -> string
val pp : ?std:bool -> t Fmt.t

val parse : string -> t Run.t
val parseJsonWith : 'a decoder -> t -> 'a Run.t
val parseStringWith : 'a decoder -> string -> 'a Run.t

val mergeAssoc : (string * t) list -> (string * t) list -> (string * t) list

module Decode : sig
  val string : t -> (string, string) result
  val assoc : t -> ((string * t) list, string) result

  val nullable : 'a decoder -> 'a option decoder

  val field : name:string -> t -> (t, string) result
  val fieldOpt : name:string -> t -> (t option, string) result

  val fieldWith : name:string -> 'a decoder -> 'a decoder
  val fieldOptWith : name:string -> 'a decoder -> 'a option decoder

  val list : ?errorMsg:string -> 'a decoder -> 'a list decoder
  val stringMap : ?errorMsg:string -> 'a decoder -> 'a StringMap.t decoder

  val cmd : ?errorMsg:string -> Cmd.t decoder
end

module Encode : sig
  val opt : 'a encoder -> 'a option encoder
  val list : 'a encoder -> 'a list encoder
  val string : string -> t
end
