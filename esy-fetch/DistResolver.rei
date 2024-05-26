open EsyPackageConfig;

/**

  Loading packages from sources and collecting overrides.

 */;

type resolution = {
  /** A set of overrides. */
  overrides: Overrides.t,
  /** Final source. */
  dist: Dist.t,
  manifest: option(manifest),
  /* In case no manifest is found - None is returned. */
  paths: Path.Set.t,
  /* Local paths used to read manifests metadata. */
}
and manifest = {
  kind: ManifestSpec.kind,
  filename: string,
  suggestedPackageName: string,
  data: string,
};

/**

  Resolve [source] and produce a [resolution].

  A set of predefined [overrides] can be passed, in this case newly discovered
  overrides are being appended to it.

  Argument [root] is used to resolve [Source.LocalPath] and
  [Source.LocalPathLink] sources.

 */

let resolve:
  (
    ~gitUsername: option(string),
    ~gitPassword: option(string),
    ~overrides: Overrides.t=?,
    ~cfg: Config.t,
    ~sandbox: SandboxSpec.t,
    ~pkgName: string,
    Dist.t
  ) =>
  RunAsync.t(resolution);
