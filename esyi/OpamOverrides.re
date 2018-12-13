type t = {
  commit: string,
  records: OpamPackage.Name.Map.t(record),
}
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
  let%bind (repoPath, commit) =
    switch (cfg.Config.esyOpamOverride) {
    | Config.Local(path) => return((path, "abcdef"))
    | Config.Remote(remote, local) =>
      let update = () => {
        let%lwt () =
          Logs_lwt.app(m => m("checking %s for updates...", remote));
        let%bind commit =
          Git.ShallowClone.update(
            ~branch=Config.esyOpamOverrideVersion,
            ~dst=local,
            remote,
          );
        return((local, commit));
      };
      if (cfg.Config.skipRepositoryUpdate) {
        if%bind (Fs.exists(local)) {
          return((local, "abcdef"));
        } else {
          update();
        };
      } else {
        update();
      };
    };
  let packagesDir = Path.(repoPath / "packages");

  let%bind names = Fs.listDir(packagesDir);
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

  return({records: overrides, commit});
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
        let%bind json = Fs.readJsonFile(Path.(path / "package.json"));
        let digest =
          Digestv.string(
            OpamPackage.Name.to_string(name)
            ++ "$$"
            ++ OpamPackage.Version.to_string(version)
            ++ "$$"
            ++ overrides.commit,
          );
        let override = Solution.Override.OfOpamOverride({digest, json, path});
        return(Some(override));
      | (None, None) => return(None)
      };
    | None => return(None)
    }
  );
