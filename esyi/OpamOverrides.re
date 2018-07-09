type t = OpamPackage.Name.Map.t(list((OpamVersion.Formula.DNF.t, Fpath.t)));

let rec yamlToJson = value =>
  switch (value) {
  | `A(items) => `List(List.map(~f=yamlToJson, items))
  | `O(items) =>
    `Assoc(
      List.map(~f=((name, value)) => (name, yamlToJson(value)), items),
    )
  | `String(s) => `String(s)
  | `Float(s) => `Float(s)
  | `Bool(b) => `Bool(b)
  | `Null => `Null
  };

let init = (~cfg, ()) : RunAsync.t(t) =>
  RunAsync.Syntax.(
    {
      let%bind repoPath =
        switch (cfg.Config.esyOpamOverride) {
        | Config.Local(path) => return(path)
        | Config.Remote(remote, local) =>
          let%bind () =
            Git.ShallowClone.update(~branch="5", ~dst=local, remote);
          return(local);
        };
      let packagesDir = Path.(repoPath / "packages");

      let%bind names = Fs.listDir(packagesDir);
      module String = Astring.String;

      let parseOverrideSpec = spec =>
        switch (String.cut(~sep=".", spec)) {
        | None => (OpamPackage.Name.of_string(spec), OpamVersion.Formula.any)
        | Some((name, constr)) =>
          let constr =
            String.map(
              fun
              | '_' => ' '
              | c => c,
              constr,
            );
          let constr = OpamVersion.Formula.parse(constr);
          (OpamPackage.Name.of_string(name), constr);
        };

      let overrides = {
        let f = (overrides, dirName) => {
          let (name, formula) = parseOverrideSpec(dirName);
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
        };
        List.fold_left(~f, ~init=OpamPackage.Name.Map.empty, names);
      };

      return(overrides);
    }
  );

let load = baseDir => {
  open RunAsync.Syntax;
  let packageJson = Path.(baseDir / "package.json");
  let packageYaml = Path.(baseDir / "package.yaml");
  if%bind (Fs.exists(packageJson)) {
    RunAsync.withContext(
      "Reading " ++ Path.toString(packageJson),
      {
        let%bind json = Fs.readJsonFile(packageJson);
        RunAsync.ofRun(
          Json.parseJsonWith(Package.OpamOverride.of_yojson, json),
        );
      },
    );
  } else {
    RunAsync.withContext(
      "Reading " ++ Path.toString(packageYaml),
      if%bind (Fs.exists(packageYaml)) {
        let%bind data = Fs.readFile(packageYaml);
        let%bind yaml =
          Yaml.of_string(data) |> Run.ofBosError |> RunAsync.ofRun;
        let json = yamlToJson(yaml);
        RunAsync.ofRun(
          Json.parseJsonWith(Package.OpamOverride.of_yojson, json),
        );
      } else {
        error(
          "must have either package.json or package.yaml "
          ++ Path.toString(baseDir),
        );
      },
    );
  };
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
