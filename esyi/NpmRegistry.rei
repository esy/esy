let versions : (~cfg: Config.t, string)
  => RunAsync.t(list((SemverVersion.Version.t, Manifest.t)));

let version : (~cfg: Config.t, string, SemverVersion.Version.t)
  => RunAsync.t(Manifest.t);
