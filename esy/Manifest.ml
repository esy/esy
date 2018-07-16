module CommandList = struct

  module Command = struct

    type t =
      | Parsed of string list
      | Unparsed of string
      [@@deriving (show, to_yojson, eq, ord)]

    let of_yojson (json : Json.t) =
      match json with
      | `String command -> Ok (Unparsed command)
      | `List command ->
        begin match Json.Parse.(list string (`List command)) with
        | Ok args -> Ok (Parsed args)
        | Error err -> Error err
        end
      | _ -> Error "expected either a string or an array of strings"

  end

  type t =
    Command.t list option
    [@@deriving (show, eq, ord)]

  let of_yojson (json : Json.t) =
    let open Result.Syntax in
    let commands =
      match json with
      | `Null -> Ok []
      | `List commands ->
        Json.Parse.list Command.of_yojson (`List commands)
      | `String command ->
        let%bind command = Command.of_yojson (`String command) in
        Ok [command]
      | _ -> Error "expected either a null, a string or an array"
    in
    match%bind commands with
    | [] -> Ok None
    | commands -> Ok (Some commands)

  let to_yojson commands =
    match commands with
    | None -> `List []
    | Some commands -> `List (List.map ~f:Command.to_yojson commands)

end

module Scripts = struct

  type script = {
    command : Cmd.t;
  }
  [@@deriving (show, eq, ord)]

  type t =
    script StringMap.t
    [@@deriving (eq, ord)]

  let empty = StringMap.empty

  let pp =
    let open Fmt in
    let ppBinding = hbox (pair (quote string) (quote pp_script)) in
    vbox ~indent:1 (iter_bindings ~sep:comma StringMap.iter ppBinding)

  let of_yojson =
    let errorMsg =
      "A command in \"scripts\" expects a string or an array of strings"
    in
    let script (json: Json.t) =
      match Json.Parse.cmd ~errorMsg json with
      | Ok command -> Ok {command;}
      | Error err -> Error err
    in
    Json.Parse.stringMap script

  let find (cmd: string) (scripts: t) = StringMap.find_opt cmd scripts

  type scripts = t
  let scripts_of_yojson = of_yojson

  module ParseManifest = struct
    type t = {
      scripts: (scripts [@default empty]);
    } [@@deriving (of_yojson { strict = false })]

    let parse json =
      match of_yojson json with
      | Ok pkg -> Ok pkg.scripts
      | Error err -> Error err
  end

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind json = Fs.readJsonFile path in
    RunAsync.ofRun (
      let open Run.Syntax in
      let%bind data = Json.parseJsonWith ParseManifest.of_yojson json in
      return data.ParseManifest.scripts
    )
end

(**
 * Environment for the entire sandbox as specified in "esy.sandboxEnv".
 *)
module SandboxEnv = struct

  type item = {
    name : string;
    value : string;
  }
  [@@deriving (show, eq, ord)]

  type t =
    item list
    [@@deriving (show, eq, ord)]

  let empty = []

  let of_yojson = function
    | `Assoc items ->
      let open Result.Syntax in
      let f items ((k, v): (string * Yojson.Safe.json)) = match v with
      | `String value ->
        Ok ({name = k; value;}::items)
      | _ -> Error "expected string"
      in
      let%bind items = Result.List.foldLeft ~f ~init:[] items in
      Ok (List.rev items)
    | _ -> Error "expected an object"
end

(**
 * Environment exported from a package as specified in "esy.exportedEnv".
 *)
module ExportedEnv = struct

  type scope =
    | Local
    | Global
    [@@deriving (show, eq, ord)]

  let scope_of_yojson = function
    | `String "global" -> Ok Global
    | `String "local" -> Ok Local
    | _ -> Error "expected either \"local\" or \"global\""

  module Item = struct
    type t = {
      value : string [@key "val"];
      scope : (scope [@default Local]);
      exclusive : (bool [@default false]);
    }
    [@@deriving of_yojson]
  end

  type item = {
    name : string;
    value : string;
    scope : scope;
    exclusive : bool;
  }
  [@@deriving (show, eq, ord)]

  type t =
    item list
    [@@deriving (show, eq, ord)]

  let empty = []

  let of_yojson = function
    | `Assoc items ->
      let open Result.Syntax in
      let f items (k, v) =
        let%bind {Item. value; scope; exclusive} = Item.of_yojson v in
        Ok ({name = k; value; scope; exclusive}::items)
      in
      let%bind items = Result.List.foldLeft ~f ~init:[] items in
      Ok (List.rev items)
    | _ -> Error "expected an object"

end

module BuildType = struct
  type t =
    | InSource
    | OutOfSource
    | JBuilderLike
    [@@deriving (show, eq, ord)]

  let of_yojson = function
    | `String "_build" -> Ok JBuilderLike
    | `Bool true -> Ok InSource
    | `Bool false -> Ok OutOfSource
    | _ -> Error "expected false, true or \"_build\""

end

module SourceType = struct
  type t =
    | Immutable
    | Development
    [@@deriving (show, eq, ord)]
end

module EsyReleaseConfig = struct
  type t = {
    releasedBinaries: string list;
    deleteFromBinaryRelease: (string list [@default []]);
  } [@@deriving (show, of_yojson { strict = false })]
end

module EsyManifest = struct

  type t = {
    build: (CommandList.t [@default None]);
    install: (CommandList.t [@default None]);
    buildsInSource: (BuildType.t [@default BuildType.OutOfSource]);
    exportedEnv: (ExportedEnv.t [@default []]);
    sandboxEnv: (SandboxEnv.t [@default []]);
    release: (EsyReleaseConfig.t option [@default None]);
  } [@@deriving (show, of_yojson { strict = false })]

  let empty = {
    build = None;
    install = None;
    buildsInSource = BuildType.OutOfSource;
    exportedEnv = [];
    sandboxEnv = [];
    release = None;
  }
end

module Esy = struct

  module Dependencies = struct
    type t = string StringMap.t

    let empty = StringMap.empty
    let keys = StringMap.keys

    let pp =
      let open Fmt in
      let ppBinding = hbox (pair (quote string) (quote string)) in
      vbox ~indent:1 (iter_bindings ~sep:comma StringMap.iter ppBinding)

    let of_yojson =
      Json.Parse.(stringMap string)

  end

  type t = {
    name : string;
    version : string;
    description : (string option [@default None]);
    license : (Json.t option [@default None]);
    dependencies : (Dependencies.t [@default Dependencies.empty]);
    peerDependencies : (Dependencies.t [@default Dependencies.empty]);
    devDependencies : (Dependencies.t [@default Dependencies.empty]);
    optDependencies : (Dependencies.t [@default Dependencies.empty]);
    buildTimeDependencies : (Dependencies.t [@default Dependencies.empty]);
    esy: EsyManifest.t option [@default None];
    _resolved: (string option [@default None]);
  } [@@deriving (show, of_yojson {strict = false})]

  let name manifest = manifest.name
  let version manifest = manifest.version

  let dependencies manifest =
    StringSet.of_list (
      (Dependencies.keys manifest.dependencies)
      @ (Dependencies.keys manifest.peerDependencies)
    )

  let devDependencies manifest =
    StringSet.of_list (Dependencies.keys manifest.devDependencies)

  let optDependencies manifest =
    StringSet.of_list (Dependencies.keys manifest.optDependencies)

  let buildTimeDependencies manifest =
    StringSet.of_list (Dependencies.keys manifest.buildTimeDependencies)

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind json = Fs.readJsonFile path in
    RunAsync.ofRun (Json.parseJsonWith of_yojson json)

end

module OpamOverride = struct
  type t = {
    build : (CommandList.t option [@default None]);
    install : (CommandList.t option [@default None]);
    exportedEnv : (ExportedEnv.t [@default ExportedEnv.empty]);
    dependencies : (Esy.Dependencies.t [@default Esy.Dependencies.empty]);

  } [@@deriving of_yojson {strict = false}]

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind json = Fs.readJsonFile path in
    RunAsync.ofRun (Json.parseJsonWith of_yojson json)

end

module Opam = struct
  type t = {
    opam : OpamFile.OPAM.t;
    override : OpamOverride.t option;
  }

  let opamName {opam;_} =
    let name = OpamFile.OPAM.name opam in
    OpamPackage.Name.to_string name

  let name manifest =
    "@opam/" ^ (opamName manifest)

  let version {opam;_} =
    let version = OpamFile.OPAM.version opam in
    OpamPackage.Version.to_string version

  let listPackageNamesOfFormula ~build ~test ~post ~doc ~dev formula =
    let formula =
      let env var =
        match OpamVariable.Full.to_string var with
        | "test" -> Some (OpamVariable.B test)
        | _ -> None
      in
      OpamFilter.partial_filter_formula env formula
    in
    let formula =
      OpamFilter.filter_deps
        ~build ~post ~test ~doc ~dev
        formula
    in
    let atoms = OpamFormula.atoms formula in
    let f (name, _) =
      let name = OpamPackage.Name.to_string name in
      "@opam/" ^ name
    in
    List.map ~f atoms

  let dependencies {opam; override} =

    let f = OpamFile.OPAM.depends opam in

    let f =
      let env var =
        match OpamVariable.Full.to_string var with
        | "test" -> Some (OpamVariable.B false)
        | "doc" -> Some (OpamVariable.B false)
        | _ -> None
      in
      OpamFilter.partial_filter_formula env f
    in

    let dependencies =
      listPackageNamesOfFormula
        ~build:true ~test:false ~post:true ~doc:false ~dev:false
        f
    in
    let dependencies =
      "ocaml"
      ::"@esy-ocaml/esy-installer"
      ::"@esy-ocaml/substs"
      ::dependencies
    in
    let dependencies =
      match override with
      | Some {OpamOverride. dependencies = overrideDependencies; _} ->
        (StringMap.keys overrideDependencies) @ dependencies
      | None -> dependencies
    in
    StringSet.of_list dependencies

  let optDependencies {opam;_} =
    let dependencies =
      listPackageNamesOfFormula
        ~build:true ~test:false ~post:true ~doc:false ~dev:false
        (OpamFile.OPAM.depopts opam)
    in
    StringSet.of_list dependencies

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind opam =
      let filename = OpamFile.make (OpamFilename.of_string (Path.toString path)) in
      let%bind data = Fs.readFile path in
      return (OpamFile.OPAM.read_from_string ~filename data)
    in
    return {opam; override = None}
end

type t =
  | Esy of Esy.t
  | Opam of Opam.t

let ofDir (path : Path.t) =
  let open RunAsync.Syntax in
  let filename = Path.(path / "esy.json") in
  if%bind Fs.exists filename
  then
    let%bind manifest = Esy.ofFile filename in
    return (Some (Esy manifest, filename))
  else
    let filename = Path.(path / "package.json") in
    if%bind Fs.exists filename
    then
      let%bind manifest = Esy.ofFile filename in
      return (Some (Esy manifest, filename))
    else
      let filename = Path.(path / "_esy" / "opam") in
      let overrideFilename = Path.(path / "_esy" / "override.json") in
      if%bind Fs.exists filename
      then
        let%bind manifest = Opam.ofFile filename in
        let%bind manifest =
          if%bind Fs.exists overrideFilename
          then
            let%bind override = OpamOverride.ofFile overrideFilename in
            return {manifest with Opam. override = Some override}
          else return manifest
        in
        return (Some (Opam manifest, filename))
      else
        return None
