type t =
  | Npm(SemverVersion.Version.t)
  | Opam(OpamPackageVersion.Version.t)
  | Source(Source.t);

include S.COMMON with type t := t;

let parse: (~tryAsOpam: bool=?, string) => result(t, string);
let parseExn: string => t;

let showSimple: t => string;

module Map: Map.S with type key := t;
module Set: Set.S with type elt := t;
