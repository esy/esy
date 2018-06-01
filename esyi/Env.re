type resolved = (
  string,
  PackageJson.DependencyRequest.req,
  Solution.Version.t,
);

type fullPackage = {
  name: string,
  version: Solution.Version.t,
  source: Types.PendingSource.t,
  requested: PackageJson.DependenciesInfo.t,
  runtime: list(resolved),
  build: list(resolved),
};

type rootPackage = {
  package: fullPackage,
  runtimeBag: list(fullPackage),
};

type target =
  | Default
  | Arch(string)
  | ArchSubArch(string, string);

type t = {
  targets: list((target, rootPackage)),
  buildDependencies: list(rootPackage),
};
