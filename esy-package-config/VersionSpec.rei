/**
 * This representes a concrete version which at some point will be resolved to a
 * concrete version Version.t.
 */;

type t =
  | Npm(SemverVersion.Formula.DNF.t)
  | NpmDistTag(string)
  | Opam(OpamPackageVersion.Formula.DNF.t)
  | Source(SourceSpec.t);

include S.COMPARABLE with type t := t;
include S.PRINTABLE with type t := t;

let to_yojson: Json.encoder(t);

let parserNpm: Parse.t(t);
let parserOpam: Parse.t(t);

let ofVersion: Version.t => t;
