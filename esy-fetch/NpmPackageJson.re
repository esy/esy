module Lifecycle = {
  [@deriving of_yojson({strict: false})]
  type t = {
    postinstall: [@default None] option(string),
    install: [@default None] option(string),
  };
};

module Bin = {
  type t =
    | Empty
    | One(string)
    | Many(StringMap.t(string));

  let of_yojson =
    Result.Syntax.(
      fun
      | `String(cmd) => {
          let cmd = String.trim(cmd);
          switch (cmd) {
          | "" => return(Empty)
          | cmd => return(One(cmd))
          };
        }
      | `Assoc(items) => {
          let* items = {
            let f = (cmds, (name, json)) =>
              switch (json) {
              | `String(cmd) => return(StringMap.add(name, cmd, cmds))
              | _ => error("expected a string")
              };

            Result.List.foldLeft(~f, ~init=StringMap.empty, items);
          };

          return(Many(items));
        }
      | _ => error("expected a string or an object")
    );
};

[@deriving of_yojson({strict: false})]
type json = {
  [@default None]
  name: option(string),
  bin: [@default Bin.Empty] Bin.t,
  scripts: [@default None] option(Lifecycle.t),
  esy: [@default None] option(Json.t),
};

[@deriving of_yojson({strict: false})]
type t = {
  basePath: Path.t,
  json,
};

type lifecycle =
  Lifecycle.t = {
    postinstall: option(string),
    install: option(string),
  };

let ofDir = path => {
  open RunAsync.Syntax;
  if%bind (Fs.exists(Path.(path / "esy.json"))) {
    return(None);
  } else {
    let filename = Path.(path / "package.json");
    if%bind (Fs.exists(filename)) {
      let* json = Fs.readJsonFile(filename);
      let* manifest =
        RunAsync.ofRun(Json.parseJsonWith(json_of_yojson, json));
      if (Option.isSome(manifest.esy)) {
        return(None);
      } else {
        return(Some({basePath: path, json: manifest}));
      };
    } else {
      return(None);
    };
  };
};

let bin = ({basePath, json: pkgJson}) => {
  let makePathToCmd = cmdPath => Path.(basePath /\/ v(cmdPath) |> normalize);
  switch (pkgJson.bin, pkgJson.name) {
  | (Bin.One(cmd), Some(name)) => [(name, makePathToCmd(cmd))]
  | (Bin.One(cmd), None) =>
    let cmd = makePathToCmd(cmd);
    let name = Path.basename(cmd);
    [(name, cmd)];
  | (Bin.Many(cmds), _) =>
    let f = (name, cmd, cmds) => [(name, makePathToCmd(cmd)), ...cmds];
    StringMap.fold(f, cmds, []);
  | (Bin.Empty, _) => []
  };
};

let lifecycle = ({json: pkgJson, _}) =>
  switch (pkgJson.scripts) {
  | Some({Lifecycle.postinstall: None, install: None}) => None
  | lifecycle => lifecycle
  };

let setBasePath = (basePath, {json, _}) => {json, basePath};
