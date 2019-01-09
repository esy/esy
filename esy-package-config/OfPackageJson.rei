type warning = string;

/** Parse [InstallManifest.t] out of package.json data.
  */

let installManifest:
  (
    ~parseResolutions: bool=?,
    ~parseDevDependencies: bool=?,
    ~source: Source.t=?,
    ~name: string,
    ~version: Version.t,
    Json.t
  ) =>
  Run.t((InstallManifest.t, list(warning)));

/** Parse [BuildManifest.t] out of package.json data.

    Note that some package.json data don't have build manifests defined. We
    return [None] in this case.

  */

let buildManifest:
  Json.t => Run.t(option((BuildManifest.t, list(warning))));
