module Infix = {
  let (|?>>) = (a, b) =>
    switch (a) {
    | None => None
    | Some(x) => Some(b(x))
    };
  let (|?>) = (a, b) =>
    switch (a) {
    | None => None
    | Some(x) => b(x)
    };
  let (|!) = (a, b) =>
    switch (a) {
    | None => failwith(b)
    | Some(a) => a
    };
};

open Infix;

module JsonParseUtil = {
  let arr = json =>
    switch (json) {
    | `List(items) => Some(items)
    | _ => None
    };
  let obj = json =>
    switch (json) {
    | `Assoc(items) => Some(items)
    | _ => None
    };
  let str = json =>
    switch (json) {
    | `String(str) => Some(str)
    | _ => None
    };
  let get = List.assoc_opt;
  let (|.!) = (fn, message, opt) => fn(opt) |! message;
};

module OpamSection = {
  include JsonParseUtil;
  type t = {
    source: option(Types.PendingSource.t),
    files: list((Path.t, string)) /* relpath, contents */
    /* patches: list((string, string)) relpath, abspath */
  };

  let of_yojson = (json: Json.t) =>
    Ok(
      json
      |> (obj |.! "opam should be an object")
      |> (
        items => {
          let maybeArchiveSource =
            items
            |> get("url")
            |?>> (str |.! "url should be a string")
            |?>> (
              url =>
                Types.PendingSource.Archive(
                  url,
                  items
                  |> get("checksum")
                  |?>> (str |.! "checksum should be a string"),
                )
            );
          let maybeGitSource =
            items
            |> get("git")
            |?>> (str |.! "git should be a string")
            |?>> (
              git =>
                Types.PendingSource.GitSource(
                  git,
                  None /* TODO parse out commit if there */
                )
            );
          {
            source: Option.orOther(~other=maybeGitSource, maybeArchiveSource),
            files:
              Option.orDefault(
                ~default=[],
                items |> get("files") |?>> (arr |.! "files must be an array"),
              )
              |> List.map(obj |.! "files item must be an obj")
              |> List.map(items =>
                   (
                     items
                     |> get("name")
                     |?>> (str |.! "name must be a str")
                     |?>> Path.v
                     |! "name required for files",
                     items
                     |> get("content")
                     |?>> (str |.! "content must be a str")
                     |! "content required for files",
                   )
                 ),
          };
        }
      ),
    );
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

module CommandList = {
  [@deriving of_yojson]
  type t = list(Command.t);
};

module Override = {
  [@deriving of_yojson]
  type t = {
    build: [@default None] option(CommandList.t),
    install: [@default None] option(CommandList.t),
    dependencies:
      [@default PackageJson.Dependencies.empty] PackageJson.Dependencies.t,
    peerDependencies:
      [@default PackageJson.Dependencies.empty] PackageJson.Dependencies.t,
    exportedEnv:
      [@default PackageJson.ExportedEnv.empty] PackageJson.ExportedEnv.t,
    opam: [@default None] option(OpamSection.t),
  };
};

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

module ParseName = {
  let stripDash = num =>
    if (num.[0] == '-') {
      String.sub(num, 1, String.length(num) - 1);
    } else {
      num;
    };
  let stripPrefix = (text, prefix) => {
    let tl = String.length(text);
    let pl = String.length(prefix);
    if (tl > pl && String.sub(text, 0, pl) == prefix) {
      Some(String.sub(text, pl, tl - pl));
    } else {
      None;
    };
  };
  let prefixes = ["<=", ">=", "<", ">"];
  let prefix = name => {
    let rec loop = prefixes =>
      switch (prefixes) {
      | [] => (None, name)
      | [one, ...rest] =>
        switch (stripPrefix(name, one)) {
        | None => loop(rest)
        | Some(text) => (Some(one), text)
        }
      };
    loop(prefixes);
  };
  /* yaml https://github.com/avsm/ocaml-yaml
     this file https://github.com/esy/esy-install/blob/master/src/resolvers/exotics/opam-resolver/opam-repository-override.js
     also this one https://github.com/esy/esy-install/blob/master/src/resolvers/exotics/opam-resolver/opam-repository.js */
  let splitExtra = patch =>
    switch (String.split_on_char('-', patch)) {
    | [] => assert(false)
    | [one] => (one, None)
    | [one, ...rest] => (one, Some(String.concat("-", rest)))
    };
  let parseDirectoryName = name =>
    GenericVersion.(
      switch (String.split_on_char('.', name)) {
      | [] => assert(false)
      | [single] => (single, Any)
      | [name, num, "x", "x" | "x-"] => (
          name,
          And(
            AtLeast(OpamVersion.triple(int_of_string(num), 0, 0)),
            LessThan(OpamVersion.triple(int_of_string(num) + 1, 0, 0)),
          ),
        )
      | [name, num, minor, "x" | "x-"] => (
          name,
          And(
            AtLeast(
              OpamVersion.triple(
                int_of_string(num),
                int_of_string(minor),
                0,
              ),
            ),
            LessThan(
              OpamVersion.triple(
                int_of_string(num),
                int_of_string(minor) + 1,
                0,
              ),
            ),
          ),
        )
      | [name, major, minor, patch] =>
        let (prefix, major) = prefix(major);
        let (patch, extra) = splitExtra(patch);
        let version =
          Types.opamFromNpmConcrete((
            int_of_string(major),
            int_of_string(minor),
            int_of_string(patch),
            extra,
          ));
        (
          name,
          switch (prefix) {
          | None => Exactly(version)
          | Some(">") => GreaterThan(version)
          | Some(">=") => AtLeast(version)
          | Some("<") => LessThan(version)
          | Some("<=") => AtMost(version)
          | _ => assert(false)
          },
        );
      | _ => failwith("Bad override version " ++ name)
      }
    );
};

let tee = (fn, value) =>
  if (fn(value)) {
    Some(value);
  } else {
    None;
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
  return(
    List.map(
      name => {
        let (realName, semver) = ParseName.parseDirectoryName(name);
        (realName, semver, Path.(packagesDir / name));
      },
      names,
    ),
  );
};

let findApplicableOverride = (overrides, name, version) => {
  open RunAsync.Syntax;
  let rec loop =
    fun
    | [] => return(None)
    | [(oname, semver, fullPath), ..._]
        when name == oname && OpamVersion.matches(semver, version) => {
        let%bind override = getContents(fullPath);
        return(Some(override));
      }
    | [_, ...rest] => loop(rest);
  loop(overrides);
};

let applyOverride = (manifest: OpamFile.manifest, override: Override.t) => {
  let source =
    Option.orDefault(
      ~default=manifest.source,
      override.Override.opam |?> (opam => opam.OpamSection.source),
    );
  {
    ...manifest,
    build: Option.orDefault(~default=manifest.build, override.Override.build),
    install:
      Option.orDefault(~default=manifest.install, override.Override.install),
    dependencies:
      PackageJson.Dependencies.merge(
        manifest.dependencies,
        override.Override.dependencies,
      ),
    peerDependencies:
      PackageJson.Dependencies.merge(
        manifest.peerDependencies,
        override.Override.peerDependencies,
      ),
    files:
      manifest.files
      @ Option.orDefault(
          ~default=[],
          override.Override.opam |?>> (o => o.OpamSection.files),
        ),
    source,
    exportedEnv: override.Override.exportedEnv,
  };
};
