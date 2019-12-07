type local = {
  path: DistPath.t,
  manifest: option(ManifestSpec.t),
};

let compare_local: (local, local) => int;
let sexp_of_local: local => Sexplib0.Sexp.t;
let local_of_yojson: Json.decoder(local);
let local_to_yojson: Json.encoder(local);

type t =
  | Archive({
      url: string,
      checksum: Checksum.t,
    })
  | Git({
      remote: string,
      commit: string,
      manifest: option(ManifestSpec.t),
    })
  | Github({
      user: string,
      repo: string,
      commit: string,
      manifest: option(ManifestSpec.t),
    })
  | LocalPath(local)
  | NoSource;

include S.PRINTABLE with type t := t;
include S.JSONABLE with type t := t;
include S.COMPARABLE with type t := t;

let ppPretty: Fmt.t(t);
let sexp_of_t: t => Sexplib0.Sexp.t;

let parser: Parse.t(t);
let parse: string => result(t, string);

let manifest: t => option(ManifestSpec.t);

let parserRelaxed: Parse.t(t);
let parseRelaxed: string => result(t, string);

let relaxed_of_yojson: Json.decoder(t);

module Map: Map.S with type key := t;
module Set: Set.S with type elt := t;
