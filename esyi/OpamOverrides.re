type t = list((OpamFile.PackageName.t, OpamFile.Formula.t, Fpath.t));

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

module Override = {
  [@deriving of_yojson]
  type t = {
    build: [@default None] option(list(Command.t)),
    install: [@default None] option(list(Command.t)),
    dependencies:
      [@default PackageInfo.Dependencies.empty] PackageInfo.Dependencies.t,
    peerDependencies:
      [@default PackageInfo.Dependencies.empty] PackageInfo.Dependencies.t,
    exportedEnv:
      [@default PackageJson.ExportedEnv.empty] PackageJson.ExportedEnv.t,
    opam: [@default Opam.empty] Opam.t,
  };
};

type override = Override.t;

let expectResult = (message, res) =>
  switch (res) {
  | Rresult.Ok(x) => x
  | _ => failwith(message)
  };

let rec yamlToJson = value =>
  switch (value) {
  | `A(items) => `List(List.map(yamlToJson, items))
  | `O(items) =>
    `Assoc(List.map(((name, value)) => (name, yamlToJson(value)), items))
  | `String(s) => `String(s)
  | `Float(s) => `Float(s)
  | `Bool(b) => `Bool(b)
  | `Null => `Null
  };

let getContents = baseDir => {
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
        let json =
          Yaml.of_string(data) |> expectResult("Bad yaml file") |> yamlToJson;
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

let getOverrides = checkoutDir => {
  open RunAsync.Syntax;
  let packagesDir = Path.(checkoutDir / "packages");
  let%bind names = Fs.listDir(packagesDir);
  module String = Astring.String;

  let parseOverrideSpec = spec =>
    switch (String.cut(~sep=".", spec)) {
    | None => (OpamFile.PackageName.ofString(spec), OpamVersion.Formula.ANY)
    | Some((name, constr)) =>
      let constr =
        String.map(
          fun
          | '_' => ' '
          | c => c,
          constr,
        );
      let constr = OpamVersion.Formula.parse(constr);
      (OpamFile.PackageName.ofString(name), constr);
    };

  return(
    List.map(
      name => {
        let (realName, semver) = parseOverrideSpec(name);
        (realName, semver, Path.(packagesDir / name));
      },
      names,
    ),
  );
};

let findApplicableOverride =
    (overrides, name: OpamFile.PackageName.t, version) => {
  open RunAsync.Syntax;
  let rec loop =
    fun
    | [] => return(None)
    | [(oname, semver, fullPath), ..._]
        when name == oname && OpamVersion.Formula.matches(semver, version) => {
        let%bind override = getContents(fullPath);
        return(Some(override));
      }
    | [_, ...rest] => loop(rest);
  loop(overrides);
};

let applyOverride = (manifest: OpamFile.manifest, override: Override.t) => {
  let source =
    switch (override.opam.Opam.source) {
    | Some(source) => PackageInfo.Source.Archive(source.url, source.checksum)
    | None => manifest.source
    };

  let files =
    manifest.files
    @ List.map(f => Opam.(f.name, f.content), override.opam.files);
  {
    ...manifest,
    build: Option.orDefault(~default=manifest.build, override.Override.build),
    install:
      Option.orDefault(~default=manifest.install, override.Override.install),
    dependencies:
      PackageInfo.Dependencies.merge(
        manifest.dependencies,
        override.Override.dependencies,
      ),
    peerDependencies:
      PackageInfo.Dependencies.merge(
        manifest.peerDependencies,
        override.Override.peerDependencies,
      ),
    files,
    source,
    exportedEnv: override.Override.exportedEnv,
  };
};
