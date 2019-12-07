type t =
  | Dist(Dist.t)
  | Link({
      path: DistPath.t,
      manifest: option(ManifestSpec.t),
      kind: linkKind,
    })
and linkKind =
  | LinkRegular
  | LinkDev;

include S.COMMON with type t := t;

let relaxed_of_yojson: Json.decoder(t);

let sexp_of_t: t => Sexplib0.Sexp.t;
let ppPretty: Fmt.t(t);

let parser: Parse.t(t);
let parse: string => result(t, string);

let parserRelaxed: Parse.t(t);
let parseRelaxed: string => result(t, string);

let manifest: t => option(ManifestSpec.t);
let toDist: t => Dist.t;

module Map: Map.S with type key := t;
module Set: Set.S with type elt := t;
