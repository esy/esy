open Std
module StringMap = Map.Make(String)

(**
 * A list of commands as specified in "esy.build" and "esy.install".
 *)
module CommandList = struct

  module Command = struct

    type t =
      string list
      [@@deriving show, to_yojson]

    let of_yojson (json : Json.t) =
      match json with
      | `String command -> begin
        match ShellSplit.split command with
        | Ok command -> Ok command
        | Error err -> Error (Run.formatError err)
        end
      | `List command ->
        Json.Parse.(list string (`List command))
      | _ -> Error("expected either a string or an array of strings")

  end

  type t =
    Command.t list option
    [@@deriving show]

  let of_yojson (json : Json.t) =
    let open Result in
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
    | Some commands -> `List (List.map Command.to_yojson commands)

end

(**
 * Environment exported from a package as specified in "esy.exportedEnv".
 *)
module ExportedEnv = struct

  type scope =
    | Local
    | Global
    [@@deriving show]

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
  [@@deriving show]

  type t =
    item list
    [@@deriving show]

  let of_yojson = function
    | `Assoc items ->
      let open Result in
      let f items (k, v) =
        let%bind {Item. value; scope; exclusive} = Item.of_yojson v in
        Ok ({name = k; value; scope; exclusive}::items)
      in
      let%bind items = listFoldLeft ~f ~init:[] items in
      Ok (List.rev items)
    | _ -> Error "expected an object"

end

module BuildType = struct
  type t =
    | InSource
    | OutOfSource
    | JBuilderLike
    [@@deriving show]

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
    | Root
    [@@deriving show]
end

module EsyManifest = struct


  type t = {
    build: (CommandList.t [@default None]);
    install: (CommandList.t [@default None]);
    buildsInSource: (BuildType.t [@default BuildType.OutOfSource]);
    exportedEnv: (ExportedEnv.t [@default []]);
  } [@@deriving (show, of_yojson { strict = false })]

  let empty = {
    build = None;
    install = None;
    buildsInSource = BuildType.OutOfSource;
    exportedEnv = [];
  }
end

module ManifestDependencyMap = struct
  type t = string StringMap.t

  let pp =
    let open Fmt in
    let ppBinding = hbox (pair (quote string) (quote string)) in
    vbox ~indent:1 (iter_bindings ~sep:comma StringMap.iter ppBinding)

  let of_yojson =
    Json.Parse.(stringMap string)

end

module Manifest = struct
  type t = {
    name : string;
    version : string;
    dependencies : (ManifestDependencyMap.t [@default StringMap.empty]);
    peerDependencies : (ManifestDependencyMap.t [@default StringMap.empty]);
    devDependencies : (ManifestDependencyMap.t [@default StringMap.empty]);
    optDependencies : (ManifestDependencyMap.t [@default StringMap.empty]);
    esy: EsyManifest.t option [@default None];
    _resolved: (string option [@default None]);
  } [@@deriving (show, of_yojson { strict = false })]

  let ofFile path =
    let open RunAsync.Syntax in
    if%bind (Fs.exists path) then (
      let%bind json = Fs.readJsonFile path in
      match of_yojson json with
      | Ok manifest -> return (Some manifest)
      | Error err -> error err
    ) else
      return None

  let ofDir (path : Path.t) =
    let open RunAsync.Syntax in
    let esyJson = Path.(path / "esy.json")
    and packageJson = Path.(path / "package.json")
    in match%bind ofFile esyJson with
    | None -> begin match%bind ofFile packageJson with
      | Some manifest -> return (Some (manifest, packageJson))
      | None -> return None
      end
    | Some manifest -> return (Some (manifest, esyJson))
end

type t = {
  id : string;
  name : string;
  version : string;
  dependencies : dependencies;
  buildCommands : CommandList.t;
  installCommands : CommandList.t;
  buildType : BuildType.t;
  sourceType : SourceType.t;
  exportedEnv : ExportedEnv.t;
  sourcePath : Config.ConfigPath.t;
}
[@@deriving show]

and dependencies =
  dependency list
  [@@deriving show]

and dependency =
  | Dependency of t
  | PeerDependency of t
  | OptDependency of t
  | DevDependency of t
  | InvalidDependency of {
    pkgName: string;
    reason: string;
  }
  [@@deriving show]

type pkg = t
type pkg_dependency = dependency

module DependencyGraph = DependencyGraph.Make(struct

  type t = pkg

  let compare a b = compare a b

  module Dependency = struct
    type t = pkg_dependency
    let compare a b = compare a b
  end

  let id (pkg : t) = pkg.id

  let traverse pkg =
    let f acc dep = match dep with
      | Dependency pkg
      | OptDependency pkg
      | DevDependency pkg
      | PeerDependency pkg -> (pkg, dep)::acc
      | InvalidDependency _ -> acc
    in
    pkg.dependencies
    |> ListLabels.fold_left ~f ~init:[]
    |> ListLabels.rev
end)
