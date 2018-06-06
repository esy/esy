let versions : (~cfg: Config.t, string)
  => RunAsync.t(list((NpmVersion.Version.t, PackageJson.t)));

let version : (~cfg: Config.t, string, NpmVersion.Version.t)
  => RunAsync.t(PackageJson.t);
