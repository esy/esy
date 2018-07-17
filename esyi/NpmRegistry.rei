let versions : (
  ~fullMetadata: bool=?,
  ~cfg: Config.t,
  ~name: string,
  unit
) => RunAsync.t(list((SemverVersion.Version.t, Manifest.t)));

let version : (
  ~cfg: Config.t,
  ~name: string,
  ~version: SemverVersion.Version.t,
  unit
) => RunAsync.t(Manifest.t);
