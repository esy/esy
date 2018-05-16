open Shared;

module Infix = {
  let (|?>) = (a, b) => switch a { | None => None | Some(x) => b(x) };
  let (|?>>) = (a, b) => switch a { | None => None | Some(x) => Some(b(x)) };
  let (|?) = (a, b) => switch a { | None => b | Some(a) => a };
  let (|??) = (a, b) => switch a { | None => b | Some(a) => Some(a) };
  let (|!) = (a, b) => switch a { | None => failwith(b) | Some(a) => a };
};
open Infix;

type opamSection = {
  source: option(Types.PendingSource.t),
  files: list((string, string)), /* relpath, contents */
  /* patches: list((string, string)) relpath, abspath */
};

type opamPackageOverride = {
  build: option(list(list(string))),
  install: option(list(list(string))),
  dependencies: list((string, string)),
  peerDependencies: list((string, string)),
  exportedEnv: list((string, (string, string))),
  opam: option(opamSection)
};

let expectResult = (message, res) => switch res {
| Rresult.Ok(x) => x
| _ => failwith(message)
};

let rec yamlToJson = value => switch value {
| `A(items) => `List(List.map(yamlToJson, items))
| `O(items) => `Assoc(List.map(((name, value)) => (name, yamlToJson(value)), items))
| `String(s) => `String(s)
| `Float(s) => `Float(s)
| `Bool(b) => `Bool(b)
| `Null => `Null
};

let module ProcessJson = {

  let arr = json => switch json {
  | `List(items) => Some(items)
  | _ => None
  };
  let obj = json => switch json {
  | `Assoc(items) => Some(items)
  | _ => None
  };
  let str = json => switch json {
  | `String(str) => Some(str)
  | _ => None
  };
  let get = List.assoc_opt;
  let (|.!) = (fn, message) => opt => fn(opt) |! message;

  let parseExportedEnv = items => {
    items
    |> List.assoc_opt("exportedEnv")
    |?>> (obj |.! "exportedEnv should be an object") |?>> List.map(((name, value)) => {
      (name, switch value {
      | `String(s) => (s, "global")
      | `Assoc(items) => (
          List.assoc_opt("val", items) |?> str |! "must have val",
          List.assoc_opt("scope", items) |?> str |? "global"
        )
      | _ => failwith("env value should be a string or an object")
      })
    })
  };

  let parseCommandList = json => json
    |> (arr |.! "should be a list")
    |> List.map(items => items |> (fun
    | `String(s) => [`String(s)]
    | `List(s) => s
    | _ => failwith("must be a string or list of strings")
    ) |> List.map(str |.! "command list item should be a string"));

  let parseDependencies = json => json
    |> (obj |.! "dependencies should be an object")
    |> List.map(((name, value)) => (name, value |> str |! "dep value must be a string"));

  let parseOpam = json => {
    json
    |> (obj |.! "opam should be an object")
    |> items => {
      let maybeArchiveSource = items |> get("url") |?>> (str |.! "url should be a string")
        |?>> (url => Types.PendingSource.Archive(url, items |> get("checksum") |?>> (str |.! "checksum should be a string")));
      let maybeGitSource = (items |> get("git") |?>> (str |.! "git should be a string") |?>> (git => Types.PendingSource.GitSource(git, None /* TODO parse out commit if there */)));
      {
      source: maybeArchiveSource |?? maybeGitSource,
      files: items |> get("files") |?>> (arr |.! "files must be an array") |? []
        |> List.map(obj |.! "files item must be an obj")
        |> List.map(items => (
          items |> get("name") |?>> (str |.! "name must be a str") |! "name required for files",
          items |> get("content") |?>> (str |.! "content must be a str") |! "content required for files"
        )),
    }}
  };

  let process = json => {
    let items = json |> obj |! "Json must be an object";
    let attr = name => items |> List.assoc_opt(name);
    {
      build: attr("build") |?>> parseCommandList,
      install: attr("install") |?>> parseCommandList,
      dependencies: attr("dependencies") |?>> parseDependencies |? [],
      peerDependencies: attr("peerDependencies") |?>> parseDependencies |? [],
      exportedEnv: parseExportedEnv(items) |? [],
      opam: attr("opam") |?>> parseOpam
    }
  };
};

let module ParseName = {
  let stripDash = num => {
    if (num.[0] == '-') {
      String.sub(num, 1, String.length(num) - 1)
    } else {
      num
    }
  };

  let stripPrefix = (text, prefix) => {
    let tl = String.length(text);
    let pl = String.length(prefix);
    if (tl > pl && String.sub(text, 0, pl) == prefix) {
      Some(String.sub(text, pl, tl - pl))
    } else {
      None
    }
  };

  let prefixes = ["<=", ">=", "<", ">"];

  let prefix = (name) => {
    let rec loop = (prefixes) => {
      switch prefixes {
      | [] => (None, name)
      | [one, ...rest] => {
        switch (stripPrefix(name, one)) {
        | None => loop(rest)
        | Some(text) => (Some(one), text)
        }
      }
      }
    };
    loop(prefixes)
  };

  /* yaml https://github.com/avsm/ocaml-yaml
  this file https://github.com/esy/esy-install/blob/master/src/resolvers/exotics/opam-resolver/opam-repository-override.js
  also this one https://github.com/esy/esy-install/blob/master/src/resolvers/exotics/opam-resolver/opam-repository.js */

  let splitExtra = (patch) => {
    switch (String.split_on_char('-', patch)) {
    | [] => assert(false)
    | [one] => (one, None)
    | [one, ...rest] => (one, Some(String.concat("-", rest)))
    }
  };

  let parseDirectoryName = (name) => {
    open Shared.GenericVersion;
    switch (String.split_on_char('.', name)) {
    | [] => assert(false)
    | [single] => (single, Any)
    | [name, num, "x", "x" | "x-"] => {
      (name,
        And(
          AtLeast(OpamVersion.triple(int_of_string(num), 0, 0)),
          LessThan(OpamVersion.triple(int_of_string(num) + 1, 0, 0))
        )
      )
    }
    | [name, num, minor, "x" | "x-"] => {
      (name,
        And(
          AtLeast(OpamVersion.triple(int_of_string(num), int_of_string(minor), 0)),
          LessThan(OpamVersion.triple(int_of_string(num), int_of_string(minor) + 1, 0))
        )
      )
    }
    | [name, major, minor, patch] => {
      let (prefix, major) = prefix(major);
      let (patch, extra) = splitExtra(patch);
      let version = Shared.Types.opamFromNpmConcrete((int_of_string(major), int_of_string(minor), int_of_string(patch), extra));
      (name, switch prefix {
      | None => Exactly(version)
      | Some(">") => GreaterThan(version)
      | Some(">=") => AtLeast(version)
      | Some("<" )=> LessThan(version)
      | Some("<=") => AtMost(version)
      | _ => assert(false)
      })
    }
    | _ => failwith("Bad override version " ++ name)
    }
  };
};

let tee = (fn, value) => if (fn(value)) { Some(value) } else { None };

let getContents = baseDir => {
  switch (tee(Files.isFile, Filename.concat(baseDir, "package.json"))) {
  | Some(name) => try (ProcessJson.process(Yojson.Basic.from_file(name))) {
  | Failure(message) => failwith("Bad json " ++ baseDir ++ " " ++ message)
  }
  | None =>
    switch (Filename.concat(baseDir, "package.yaml") |> tee(Files.isFile)) {
    | None => failwith("must have either package.json or package.yaml " ++ baseDir)
    | Some(name) => {
      let json = Yaml.of_string(Files.readFile(name) |! "unable to read yaml") |> expectResult("Bad yaml file") |> yamlToJson;
      /* print_endline(Yojson.Basic.to_string(json)); */
      try(ProcessJson.process(json)) {
      | Failure(message) => failwith("Bad yaml jsom " ++ baseDir ++ " " ++ message)
      }
    }
    }
  }
};

let getOverrides = (checkoutDir) => {
  let dir = Filename.concat(checkoutDir, "packages");
  Files.readDirectory(dir) |> List.map(name => {
    let (realName, semver) = ParseName.parseDirectoryName(name);
    (realName, semver, Filename.concat(dir, name))
  })
};

let findApplicableOverride = (overrides, name, version) => {
  let rec loop = fun
  | [] => None
  | [(oname, semver, fullPath), ..._] when name == oname && OpamVersion.matches(semver, version) => Some(getContents(fullPath))
  | [_, ...rest] => loop(rest);
  loop(overrides)
};