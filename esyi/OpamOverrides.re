type t =
  OpamPackage.Name.Map.t(list((OpamPackageVersion.Formula.DNF.t, Fpath.t)));

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

  let parseOverrideSpec = spec =>
    switch (String.cut(~sep=".", spec)) {
    | None =>
      Some((
        OpamPackage.Name.of_string(spec),
        OpamPackageVersion.Formula.any,
      ))
    | Some(("", _)) => None
    | Some((name, constr)) =>
      let constr =
        String.map(
          fun
          | '_' => ' '
          | c => c,
          constr,
        );
      let constr = OpamPackageVersion.Formula.parseExn(constr);
      Some((OpamPackage.Name.of_string(name), constr));
    };

  let overrides = {
    let f = (overrides, dirName) =>
      switch (parseOverrideSpec(dirName)) {
      | Some((name, formula)) =>
        let items =
          switch (OpamPackage.Name.Map.find_opt(name, overrides)) {
          | Some(items) => items
          | None => []
          };
        OpamPackage.Name.Map.add(
          name,
          [(formula, Path.(packagesDir / dirName)), ...items],
          overrides,
        );
      | None => overrides
      };
    List.fold_left(~f, ~init=OpamPackage.Name.Map.empty, names);
  };

  return(overrides);
};

let load = baseDir => {
  open RunAsync.Syntax;
  let packageJson = Path.(baseDir / "package.json");
  let filesPath = Path.(baseDir / "files");
  let%bind override =
    RunAsync.contextf(
      {
        let%bind json = Fs.readJsonFile(packageJson);
        RunAsync.ofRun(
          Json.parseJsonWith(Package.Overrides.override_of_yojson, json),
        );
      },
      "Reading %a",
      Path.pp,
      packageJson,
    );
  let%bind files =
    if%bind (Fs.exists(filesPath)) {
      let f = (files, path, _stat) =>
        switch (Path.relativize(~root=filesPath, path)) {
        | Some(name) =>
          let%bind file =
            Package.File.readOfPath(~prefixPath=filesPath, ~filePath=name);
          return([file, ...files]);
        | None =>
          /* This case isn't really possible but... */
          return(files)
        };
      let%bind files = Fs.fold(~init=[], ~f, filesPath);
      return(files);
    } else {
      return([]);
    };
  return({...override, Package.Overrides.files});
};

let find = (~name: OpamPackage.Name.t, ~version, overrides) =>
  RunAsync.Syntax.(
    switch (OpamPackage.Name.Map.find_opt(name, overrides)) {
    | Some(items) =>
      switch (
        List.find_opt(
          ~f=
            ((formula, _path)) =>
              OpamPackageVersion.Formula.DNF.matches(formula, ~version),
          items,
        )
      ) {
      | Some((_formula, path)) =>
        let%bind override = load(path);
        return(Some(override));
      | None => return(None)
      }
    | None => return(None)
    }
  );
