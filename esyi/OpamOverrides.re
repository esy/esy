type t = OpamPackage.Name.Map.t(list(override))
and override = {
  pattern,
  path: Path.t,
}
and pattern = {
  name: OpamPackage.Name.t,
  version: option(OpamPackage.Version.t),
};

let parseOverridePattern = pattern =>
  switch (Astring.String.cut(~sep=".", pattern)) {
  | None =>
    let name = OpamPackage.Name.of_string(pattern);
    Some({name, version: None});
  | Some(("", _)) => None
  | Some((name, constr)) =>
    let constr =
      String.map(
        fun
        | '_' => ' '
        | c => c,
        constr,
      );
    let name = OpamPackage.Name.of_string(name);
    let version = OpamPackageVersion.Version.parseExn(constr);
    Some({name, version: Some(version)});
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
      | Some(pattern) =>
        let items =
          switch (OpamPackage.Name.Map.find_opt(pattern.name, overrides)) {
          | Some(items) => items
          | None => []
          };
        OpamPackage.Name.Map.add(
          pattern.name,
          [{pattern, path: Path.(packagesDir / dirName)}, ...items],
          overrides,
        );
      | None => overrides
      };
    List.fold_left(~f, ~init=OpamPackage.Name.Map.empty, names);
  };

  return(overrides);
};

let find = (~name: OpamPackage.Name.t, ~version, overrides) =>
  RunAsync.Syntax.(
    switch (OpamPackage.Name.Map.find_opt(name, overrides)) {
    | Some(overrides) =>
      let override =
        List.find_opt(
          ~f=
            ({pattern, path: _}) =>
              switch (pattern.version) {
              | None => true
              | Some(overrideVersion) =>
                OpamPackage.Version.compare(overrideVersion, version) == 0
              },
          overrides,
        );
      switch (override) {
      | Some({pattern: _, path}) =>
        let override =
          Package.Override.ofDist(Dist.LocalPath({path, manifest: None}));
        return(Some(override));
      | None => return(None)
      };
    | None => return(None)
    }
  );
