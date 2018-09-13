type t = Yojson.Safe.json
type json = t

type 'a encoder = 'a -> t
type 'a decoder = t -> ('a, string) result

val to_yojson : t encoder
val of_yojson : t decoder

val pp : ?std:bool -> Format.formatter -> t -> unit

val mergeAssoc : (string * t) list -> (string * t) list -> (string * t) list

val parseJsonWith : ('a -> ('b, string) result) -> 'a -> 'b Run.t
val parseStringWith : (t -> ('b, string) result) -> string -> ('b, Run.error) result

module Edit : sig

  type t

  val ofJson : json -> t
  val get : string -> t -> t
  val set : string -> json -> t -> t
  val update : json -> t -> t
  val up : t -> t
  val commit : t -> (json, string) result
end

(** Combinators to decode values into json. *)
module Encode : sig

  val string : string encoder
  val list : 'a encoder -> 'a list encoder
end

(** Combinators to decode json to values. *)
module Decode : sig

  val return : 'a -> 'a decoder
  val (<$>) : ('a -> 'b) -> 'a decoder -> 'b decoder
  val (<*>) : ('a -> 'b) decoder -> 'a decoder -> 'b decoder

  val string : string decoder
  val assoc :(string * t) list decoder

  val field : name:string -> 'a decoder -> 'a decoder
  val fieldOpt : name:string -> 'a decoder -> 'a option decoder

  val list : ?errorMsg:string -> 'a decoder -> 'a list decoder
  val stringMap : ?errorMsg:string -> 'a decoder -> 'a StringMap.t decoder
end
