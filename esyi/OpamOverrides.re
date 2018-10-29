type t = OpamPackage.Name.Map.t(override)
and override = {
  default: option(Path.t),
  version: OpamPackage.Version.Map.t(Path.t),
};

let emptyOverride = {default: None, version: OpamPackage.Version.Map.empty};

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
  let%bind repoPath =
    switch (cfg.Config.esyOpamOverride) {
    | Config.Local(path) => return(path)
    | Config.Remote(remote, local) =>
      let update = () => {
        let%lwt () =
          Logs_lwt.app(m => m("checking %s for updates...", remote));
        let%bind () =
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
          | None => emptyOverride
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

  return(overrides);
};

let find = (~name: OpamPackage.Name.t, ~version, overrides) =>
  switch (OpamPackage.Name.Map.find_opt(name, overrides)) {
  | Some(override) =>
    let byVersion =
      OpamPackage.Version.Map.find_opt(version, override.version);
    switch (byVersion, override.default) {
    | (Some(path), _)
    | (None, Some(path)) =>
      let override = Package.Override.ofOpamOverride(path);
      Some(override);
    | (None, None) => None
    };
  | None => None
  };
