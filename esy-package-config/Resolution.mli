type t = {
  name : string;
  resolution : resolution;
}

and resolution =
  | Version of Version.t
  | SourceOverride of {source : Source.t; override : Json.t}

val resolution_of_yojson : resolution Json.decoder
val resolution_to_yojson : resolution Json.encoder

val digest : t -> Digestv.t

include S.COMPARABLE with type t := t
include S.PRINTABLE with type t := t
