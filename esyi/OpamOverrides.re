type t = OpamPackage.Name.Map.t(list((OpamVersion.Formula.DNF.t, Fpath.t)));

let init = (~cfg, ()) : RunAsync.t(t) =>
  RunAsync.Syntax.(
    {
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
          Some((OpamPackage.Name.of_string(spec), OpamVersion.Formula.any))
        | Some(("", _)) => None
        | Some((name, constr)) =>
          let constr =
            String.map(
              fun
              | '_' => ' '
              | c => c,
              constr,
            );
          let constr = OpamVersion.Formula.parse(constr);
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
    }
  );

let load = baseDir => {
  open RunAsync.Syntax;
  let packageJson = Path.(baseDir / "package.json");
  let filesPath = Path.(baseDir / "files");
  let%bind override =
    RunAsync.withContext(
      "Reading " ++ Path.toString(packageJson),
      {
        let%bind json = Fs.readJsonFile(packageJson);
        RunAsync.ofRun(
          Json.parseJsonWith(Package.OpamOverride.of_yojson, json),
        );
      },
    );
  let%bind files =
    if%bind (Fs.exists(filesPath)) {
      let f = (files, path, _stat) =>
        switch (Path.relativize(~root=filesPath, path)) {
        | Some(name) =>
          let%bind content = Fs.readFile(path)
          and stat = Fs.stat(path);
          let file = {Package.File.name, content, perm: stat.Unix.st_perm};
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
  return({
    ...override,
    Package.OpamOverride.opam: {
      ...override.Package.OpamOverride.opam,
      Package.OpamOverride.Opam.files,
    },
  });
};

let find = (~name: OpamPackage.Name.t, ~version, overrides) =>
  RunAsync.Syntax.(
    switch (OpamPackage.Name.Map.find_opt(name, overrides)) {
    | Some(items) =>
      switch (
        List.find_opt(
          ~f=
            ((formula, _path)) =>
              OpamVersion.Formula.DNF.matches(formula, ~version),
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
