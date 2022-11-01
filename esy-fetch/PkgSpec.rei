/** PkgSpec allows to specify a subset of packages of the sandbox. */;

open EsyPackageConfig;

type t =
  | Root
  | ByName(string)
  | ByNameVersion((string, Version.t))
  | ById(PackageId.t);

let matches: (PackageId.t, t, PackageId.t) => bool;

let pp: Fmt.t(t);
let parse: string => result(t, string);

let of_yojson: Json.decoder(t);
