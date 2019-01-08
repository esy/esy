open EsyPackageConfig;

type t;

type versions = {
  versions: list(SemverVersion.Version.t),
  distTags: StringMap.t(SemverVersion.Version.t),
};

let make: (~concurrency: int=?, ~url: string=?, unit) => t;

let versions:
  (~fullMetadata: bool=?, ~name: string, t, unit) =>
  RunAsync.t(option(versions));

let package:
  (~name: string, ~version: SemverVersion.Version.t, t, unit) =>
  RunAsync.t(InstallManifest.t);
