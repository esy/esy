(**

  A subset of yarn.lock format parser which is enough to parse .yarnrc.

 *)
type t =
  | Mapping of (string * t) list
  | Sequence of scalar list
  | Scalar of scalar

and scalar =
  | Number of float
  | String of string
  | Boolean of bool

val parse : string -> (t, string) result
(** Parses a string and returns {!type:t} value or an error. *)

val parseExn : string -> t
(** Same as {!val:parse} but raises {!exception:SyntaxError} *)

val pp : t Fmt.t

type 'a decoder = t -> ('a, string) result
type 'a scalarDecoder = scalar -> ('a, string) result

module Decode : sig
  val string : string scalarDecoder
  val number : float scalarDecoder
  val boolean : bool scalarDecoder

  val scalar : 'a scalarDecoder -> 'a decoder
  val seq : 'a scalarDecoder -> 'a list decoder

  type fields = t StringMap.t
  type 'a fieldDecoder = fields -> ('a, string) result

  val mapping : fields decoder

  val field : string -> 'a decoder -> 'a fieldDecoder
  val fieldOpt : string -> 'a decoder -> 'a option fieldDecoder
end

type 'a encoder = 'a -> t
type 'a scalarEncoder = 'a -> scalar

module Encode : sig

  val string : string scalarEncoder
  val number : float scalarEncoder
  val boolean : bool scalarEncoder

  val scalar : 'a scalarEncoder -> 'a encoder
  val seq : 'a scalarEncoder -> 'a list encoder

  type field

  val mapping : field list -> t
  val field : string -> 'a encoder -> 'a -> field
  val fieldOpt : string -> 'a encoder -> 'a option -> field
end
