[@deriving yojson]
type resolved = (string, Types.requestedDep, Solution.Version.t);

[@deriving yojson]
type fullPackage = {
  name: string,
  version: Solution.Version.t,
  source: Types.PendingSource.t,
  requested: Types.depsByKind,
  runtime: list(resolved),
  build: list(resolved),
};

[@deriving yojson]
type rootPackage = {
  package: fullPackage,
  runtimeBag: list(fullPackage),
};

[@deriving yojson]
type target =
  | Default
  | Arch(string)
  | ArchSubArch(string, string);

[@deriving yojson]
type t = {
  targets: list((target, rootPackage)),
  buildDependencies: list(rootPackage),
};
