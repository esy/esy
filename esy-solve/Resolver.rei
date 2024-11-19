/** Package request resolver */;

open EsyPackageConfig;

type t;

/** Make new resolver */

let make:
  (
    ~gitUsername: option(string),
    ~gitPassword: option(string),
    ~cfg: Config.t,
    ~sandbox: EsyFetch.SandboxSpec.t,
    unit
  ) =>
  RunAsync.t(t);

let setOCamlVersion: (Version.t, t) => unit;
let setResolutions: (Resolutions.t, t) => unit;
let getUnusedResolutions: t => list(string);

/**
 * Resolve package request into a list of resolutions
 */

let resolve:
  (~fullMetadata: bool=?, ~name: string, ~spec: VersionSpec.t=?, t) =>
  RunAsync.t(list(Resolution.t));

/**
 * Fetch the package metadata given the resolution.
 *
 * This returns an error in not valid package cannot be obtained via resolutions
 * (missing checksums, invalid dependencies format and etc.)
 */

let package:
  (~resolution: Resolution.t, t) =>
  RunAsync.t(result(InstallManifest.t, string));

let versionByNpmDistTag:
  (t, string, string) => option(SemverVersion.Version.t);
let sourceBySpec: (t, SourceSpec.t) => option(Source.t);
let getResolutions: t => Resolutions.t;
let getVersionByResolutions: (t, string) => option(Version.t);

let versionMatchesReq: (t, Req.t, string, Version.t) => bool;
let versionMatchesDep: (t, InstallManifest.Dep.t, string, Version.t) => bool;
