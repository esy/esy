module PackageNameMap = Map.Make(OpamManifest.PackageName);
module Dependencies = Package.Dependencies;

module Override = {
  module Opam = {
    [@deriving of_yojson]
    type t = {
      source: [@default None] option(source),
      files,
    }
    and source = {
      url: string,
      checksum: string,
    }
    and files = list(file)
    and file = {
      name: Path.t,
      content: string,
    };

    let empty = {source: None, files: []};
  };

  module Command = {
    type t = list(string);

    let of_yojson = (json: Json.t) =>
      switch (json) {
      | `List(_) => Json.Parse.(list(string, json))
      | `String(cmd) => Ok([cmd])
      | _ => Error("expected either a list or a string")
      };
  };

  [@deriving of_yojson]
  type t = {
    build: [@default None] option(list(Command.t)),
    install: [@default None] option(list(Command.t)),
    dependencies: [@default Package.Dependencies.empty] Package.Dependencies.t,
    peerDependencies:
      [@default Package.Dependencies.empty] Package.Dependencies.t,
    exportedEnv: [@default Package.ExportedEnv.empty] Package.ExportedEnv.t,
    opam: [@default Opam.empty] Opam.t,
  };
};

type t = PackageNameMap.t(list((OpamVersion.Formula.DNF.t, Fpath.t)));

type override = Override.t;

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
        | None => (
            OpamManifest.PackageName.ofString(spec),
            OpamVersion.Formula.any,
          )
        | Some((name, constr)) =>
          let constr =
            String.map(
              fun
              | '_' => ' '
              | c => c,
              constr,
            );
          let constr = OpamVersion.Formula.parse(constr);
          (OpamManifest.PackageName.ofString(name), constr);
        };

      let overrides = {
        let f = (overrides, dirName) => {
          let (name, formula) = parseOverrideSpec(dirName);
          let items =
            switch (PackageNameMap.find_opt(name, overrides)) {
            | Some(items) => items
            | None => []
            };
          PackageNameMap.add(
            name,
            [(formula, Path.(packagesDir / dirName)), ...items],
            overrides,
          );
        };
        List.fold_left(~f, ~init=PackageNameMap.empty, names);
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
        RunAsync.ofRun(Json.parseJsonWith(Override.of_yojson, json));
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
        RunAsync.ofRun(Json.parseJsonWith(Override.of_yojson, json));
      } else {
        error(
          "must have either package.json or package.yaml "
          ++ Path.toString(baseDir),
        );
      },
    );
  };
};

let get = (overrides, name: OpamManifest.PackageName.t, version) =>
  RunAsync.Syntax.(
    switch (PackageNameMap.find_opt(name, overrides)) {
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

let apply = (manifest: OpamManifest.t, override: Override.t) => {
  let source =
    switch (override.opam.Override.Opam.source) {
    | Some(source) => Package.Source.Archive(source.url, source.checksum)
    | None => manifest.source
    };

  let files =
    manifest.files
    @ List.map(
        ~f=f => Override.Opam.(f.name, f.content),
        override.opam.files,
      );
  {
    ...manifest,
    build: Option.orDefault(~default=manifest.build, override.Override.build),
    install:
      Option.orDefault(~default=manifest.install, override.Override.install),
    dependencies:
      Dependencies.overrideMany(
        ~reqs=Dependencies.toList(override.Override.dependencies),
        manifest.dependencies,
      ),
    peerDependencies:
      Dependencies.overrideMany(
        ~reqs=Dependencies.toList(override.Override.peerDependencies),
        manifest.peerDependencies,
      ),
    files,
    source,
    exportedEnv: override.Override.exportedEnv,
  };
};
