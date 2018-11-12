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
  | LocalPath of {
      path : DistPath.t;
      manifest : ManifestSpec.t option;
    }
  | NoSource

include S.PRINTABLE with type t := t
include S.JSONABLE with type t := t
include S.COMPARABLE with type t := t

val ppPretty : t Fmt.t
val sexp_of_t : t -> Sexplib0.Sexp.t

val parser : t Parse.t
val parse : string -> (t, string) result

val manifest : t -> ManifestSpec.t option

val parserRelaxed : t Parse.t
val parseRelaxed : string -> (t, string) result

val relaxed_of_yojson : t Json.decoder

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
