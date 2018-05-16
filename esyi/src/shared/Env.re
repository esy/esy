
module Npm = {
  [@deriving yojson]
  type t('sourceType) = {
    source: 'sourceType,
    resolved: Lockfile.realVersion,
    requested: Types.requestedDep,
    dependencies: list((string, option(t('sourceType))))
  };
};

[@deriving yojson]
type resolved = (string, Types.requestedDep, Lockfile.realVersion);

[@deriving yojson]
type fullPackage('sourceType) = {
  name: string,
  version: Lockfile.realVersion,
  source: 'sourceType, /* pending until I need to lock it down */
  requested: Types.depsByKind,
  runtime: list(resolved),
  build: list(resolved),
  npm: list((string, Npm.t('sourceType))),
};

[@deriving yojson]
type rootPackage('sourceType) = {
  package: fullPackage('sourceType),
  runtimeBag: list(fullPackage('sourceType))
};

[@deriving yojson]
type target = Default | Arch(string) | ArchSubArch(string, string);

[@deriving yojson]
type t('sourceType) = {
  targets: list((target, rootPackage('sourceType))),
  buildDependencies: list(rootPackage('sourceType))
};

let mapSnd = (mapper, (a, b)) => (a, mapper(b));
let mapOpt = (mapper, a) => switch a { | None => None | Some(x) => Some(mapper(x))};

let rec mapNpm = (mapper, npm) => {
  ...npm,
  Npm.source: mapper(npm.Npm.source),
  dependencies: List.map(mapSnd(mapOpt(mapNpm(mapper))), npm.Npm.dependencies)
};

let mapFull = (mapper, full) => {
  ...full,
  source: mapper(full.source),
  npm: List.map(mapSnd(mapNpm(mapper)), full.npm)
};

let mapRoot = (mapper, root) => {
  package: mapFull(mapper, root.package),
  runtimeBag: List.map(mapFull(mapper), root.runtimeBag)
};

let map = (mapper, t) => {
  targets: List.map(mapSnd(mapRoot(mapper)), t.targets),
  buildDependencies: List.map(mapRoot(mapper), t.buildDependencies),
};