open EsyPackageConfig;

module Scripts = {
  [@ocaml.warning "-32"];
  [@deriving ord]
  type t = StringMap.t(script)
  [@deriving ord]
  and script = {command: Command.t};

  let of_yojson = {
    let script = (json: Json.t) =>
      switch (CommandList.of_yojson(json)) {
      | Ok(command) =>
        switch (command) {
        | [] => Error("empty command")
        | [command] => Ok({command: command})
        | _ => Error("multiple script commands are not supported")
        }
      | Error(err) => Error(err)
      };

    Json.Decode.stringMap(script);
  };

  let empty = StringMap.empty;

  let find = (cmd: string, scripts: t) => StringMap.find_opt(cmd, scripts);
};

module OfPackageJson = {
  [@deriving of_yojson({strict: false})]
  type t = {
    [@default Scripts.empty]
    scripts: Scripts.t,
  };
};

type t = Scripts.t;
type script = Scripts.script = {command: Command.t};

let empty = Scripts.empty;
let find = Scripts.find;

let ofSandbox = (spec: EsyInstall.SandboxSpec.t) =>
  RunAsync.Syntax.(
    switch (spec.manifest) {
    | [@implicit_arity] EsyInstall.SandboxSpec.Manifest(Esy, filename) =>
      let%bind json = Fs.readJsonFile(Path.(spec.path / filename));
      let%bind pkgJson =
        RunAsync.ofRun(Json.parseJsonWith(OfPackageJson.of_yojson, json));
      return(pkgJson.OfPackageJson.scripts);

    | [@implicit_arity] EsyInstall.SandboxSpec.Manifest(Opam, _)
    | EsyInstall.SandboxSpec.ManifestAggregate(_) => return(Scripts.empty)
    }
  );
