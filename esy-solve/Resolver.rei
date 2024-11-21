/**

   Package request resolver.

   This module can help you,

   1. Create a resolver, [t]. Resolvers contain all the state and information to
      hit the registries/repositories and query them.
   2. Use resolvers to query package information to create [Resolutions.t]. Note
      that, packages could be remote on a registry, repository, github or be
      present locally. [Resolution.t] is a unified representation for any of
      these cases.
   3. Use [Resolution.t] to compute [InstallManifest.t].

   It also contain a bunch of useful util functions.

   Note that, [t] is a stateful/mutable type - [ocamlVersion] and [resolutions]
   (from esy.json/package.json) are explicity set later when available. (This
   could improved, perhaps set during initialisation.)


   Concepts
   --------
   Every package specified in [esy.json]/[package.json], directly or indirectly,
   is first resolved to a unified representation of it's package metadata, such
   that it can handle the following cases.

   1. Packages from opam repository
   2. Packages from NPM registry
   3. Locally present paths
   4. Github repository links

   Note that, this metadata is not the package sources themselves - repositories/registries
   only return a document/json with things like tarball URL, checksum, name, version etc.
   We call this metadata, which could be found in the above mentioned places, as a
   [InstallManifest.t]. [InstallManifest.t] representing metadata from repository/registry once again resolve to
   tarball URLs. Those representing Github repositories resolve to git URLs. Locallly available,
   package metadata, of course, resolve to file system paths.



 +-----------------+          +-----------------------+            +----------------------+
 |                 |          |                       |            |                      |
 |  @opam/foo-pkg  |--------->|  list(Resolution.t)   |----------->|   InstallManifest.t  |
 |                 |          |                       |            |                      |
 +-----------------+          +-----------------------+            +----------------------+



 */;

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

/********************** getters / setters ***********************/

let setOCamlVersion: (Version.t, t) => unit;
let setResolutions: (Resolutions.t, t) => unit;

/*************************** utils ****************************/

let getUnusedResolutions: t => list(string);
let versionByNpmDistTag:
  (t, string, string) => option(SemverVersion.Version.t);
let sourceBySpec: (t, SourceSpec.t) => option(Source.t);
let getResolutions: t => Resolutions.t;
let getVersionByResolutions: (t, string) => option(Version.t);

let versionMatchesReq: (t, Req.t, string, Version.t) => bool;
let versionMatchesDep: (t, InstallManifest.Dep.t, string, Version.t) => bool;
