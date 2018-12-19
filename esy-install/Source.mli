type link = {
  path : DistPath.t;
  manifest : ManifestSpec.t option;
}

val link_to_yojson : link Json.encoder
val link_of_yojson : link Json.decoder

type t =
  | Dist of Dist.t
  | Link of link

include S.COMMON with type t := t

val relaxed_of_yojson : t Json.decoder

val sexp_of_t : t -> Sexplib0.Sexp.t
val ppPretty : t Fmt.t

val parser : t Parse.t
val parse : string -> (t, string) result

val parserRelaxed : t Parse.t
val parseRelaxed : string -> (t, string) result

val manifest : t -> ManifestSpec.t option
val toDist : t -> Dist.t

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
