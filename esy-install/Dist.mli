type local = {
  path : DistPath.t;
  manifest : ManifestSpec.Filename.t option;
}

val compare_local : local -> local -> int
val sexp_of_local : local -> Sexplib0.Sexp.t
val local_of_yojson : local Json.decoder
val local_to_yojson : local Json.encoder

type t =
  | Archive of {
      url : string;
      checksum : Checksum.t;
    }
  | Git of {
      remote : string;
      commit : string;
      manifest : ManifestSpec.Filename.t option;
    }
  | Github of {
      user : string;
      repo : string;
      commit : string;
      manifest : ManifestSpec.Filename.t option;
    }
  | LocalPath of local
  | NoSource

include S.PRINTABLE with type t := t
include S.JSONABLE with type t := t
include S.COMPARABLE with type t := t

val ppPretty : t Fmt.t
val sexp_of_t : t -> Sexplib0.Sexp.t

val parser : t Parse.t
val parse : string -> (t, string) result

val manifest : t -> ManifestSpec.Filename.t option

val parserRelaxed : t Parse.t
val parseRelaxed : string -> (t, string) result

val relaxed_of_yojson : t Json.decoder

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
