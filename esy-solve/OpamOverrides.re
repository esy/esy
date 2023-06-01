open EsyPackageConfig;

type t = {records: OpamPackage.Name.Map.t(record)}
and record = {
  default: option(Path.t),
  version: OpamPackage.Version.Map.t(Path.t),
};

let emptyRecord = {default: None, version: OpamPackage.Version.Map.empty};

let parseOverridePattern = pattern =>
  switch (Astring.String.cut(~sep=".", pattern)) {
  | None =>
    let name = OpamPackage.Name.of_string(pattern);
    Some((name, None));
  | Some(("", _)) => None
  | Some((name, version)) =>
    let name = OpamPackage.Name.of_string(name);
    let version = OpamPackageVersion.Version.parseExn(version);
    Some((name, Some(version)));
  };

let init = (~cfg, ()): RunAsync.t(t) => {
  open RunAsync.Syntax;
  let* repoPath =
    switch (cfg.Config.esyOpamOverride) {
    | Config.Local(path) => return(path)
    | Config.Remote(remote, local) =>
      let update = () => {
        let%lwt () =
          Esy_logs_lwt.app(m => m("checking %s for updates...", remote));
        let* () =
          Git.ShallowClone.update(
            ~branch=Config.esyOpamOverrideVersion,
            ~dst=local,
            remote,
          );
        return(local);
      };
      if (cfg.Config.skipRepositoryUpdate) {
        if%bind (Fs.exists(local)) {
          return(local);
        } else {
          update();
        };
      } else {
        update();
      };
    };
  let packagesDir = Path.(repoPath / "packages");

  let* names = Fs.listDir(packagesDir);
  module String = Astring.String;

  let overrides = {
    let f = (overrides, dirName) =>
      switch (parseOverridePattern(dirName)) {
      | Some((name, version)) =>
        let path = Path.(packagesDir / dirName);
        let override =
          switch (OpamPackage.Name.Map.find_opt(name, overrides)) {
          | Some(override) => override
          | None => emptyRecord
          };
        let override =
          switch (version) {
          | None => {...override, default: Some(path)}
          | Some(version) => {
              ...override,
              version:
                OpamPackage.Version.Map.add(version, path, override.version),
            }
          };
        OpamPackage.Name.Map.add(name, override, overrides);
      | None => overrides
      };
    List.fold_left(~f, ~init=OpamPackage.Name.Map.empty, names);
  };

  return({records: overrides});
};

let find = (~name: OpamPackage.Name.t, ~version, overrides) =>
  RunAsync.Syntax.(
    switch (OpamPackage.Name.Map.find_opt(name, overrides.records)) {
    | Some(override) =>
      let byVersion =
        OpamPackage.Version.Map.find_opt(version, override.version);
      switch (byVersion, override.default) {
      | (Some(path), _)
      | (None, Some(path)) =>
        let* json = Fs.readJsonFile(Path.(path / "package.json"));
        let override = Override.OfOpamOverride({json, path});
        return(Some(override));
      | (None, None) => return(None)
      };
    | None => return(None)
    }
  );
