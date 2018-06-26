let versions : (~cfg: Config.t, string)
  => RunAsync.t(list((NpmVersion.Version.t, Manifest.t)));

let version : (~cfg: Config.t, string, NpmVersion.Version.t)
  => RunAsync.t(Manifest.t);
