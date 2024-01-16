open EsyPackageConfig;

let fetch = (cfg, sandbox, override: EsyPackageConfig.Override.t) =>
  RunAsync.Syntax.(
    switch (override) {
    | OfJson(_) => return([])
    | OfDist(info) =>
      let* path =
        DistStorage.fetchIntoCache(cfg, sandbox, info.dist, None, None);
      File.ofDir(Path.(path / "files"));
    | OfOpamOverride(info) => File.ofDir(Path.(info.path / "files"))
    }
  );
