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
      path : Path.t;
      manifest : ManifestSpec.Filename.t option;
    }
  | LocalPathLink of {
      path : Path.t;
      manifest : ManifestSpec.Filename.t option;
    }
  | NoSource

include S.COMMON with type t := t

val sexp_of_t : t -> Sexplib0.Sexp.t
val ppPretty : t Fmt.t

val parser : t Parse.t
val parse : string -> (t, string) result

val parserRelaxed : t Parse.t
val parseRelaxed : string -> (t, string) result

val manifest : t -> ManifestSpec.Filename.t option

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
