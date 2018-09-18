type t =
  | Archive of {
      url : string;
      checksum : Checksum.t;
    }
  | Git of {
      remote : string;
      commit : string;
      manifest : SandboxSpec.ManifestSpec.t option;
    }
  | Github of {
      user : string;
      repo : string;
      commit : string;
      manifest : SandboxSpec.ManifestSpec.t option;
    }
  | LocalPath of {
      path : Path.t;
      manifest : SandboxSpec.ManifestSpec.t option;
    }
  | LocalPathLink of {
      path : Path.t;
      manifest : SandboxSpec.ManifestSpec.t option;
    }
  | NoSource

include S.COMMON with type t := t

val parser : t Parse.t
val parse : string -> (t, string) result

val manifest : t -> SandboxSpec.ManifestSpec.t option

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
