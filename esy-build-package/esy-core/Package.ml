module StringMap = Map.Make(String)

(**
 * A list of commands as specified in "esy.build" and "esy.install".
 *)
module CommandList = struct

  (**
   * A single command.
   *)
  module Command = struct

    type t =
      string list
      [@@deriving show]

    let of_yojson (json : Json.t) =
      match json with
      | `String command ->
        let command = ShellSplit.split command in
        Ok command
      | `List command ->
        Json.Parse.(list string (`List command))
      | _ -> Error("expected either a string or an array of strings")

  end

  type t =
    Command.t list option
    [@@deriving show]

  let of_yojson (json : Json.t) =
    let open EsyLib.Result in
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

end

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
      let open EsyLib.Result in
      let f items (k, v) =
        let%bind {Item. value; scope; exclusive} = Item.of_yojson v in
        Ok ({name = k; value; scope; exclusive}::items)
      in
      let%bind items = listFoldLeft ~f ~init:[] items in
      Ok (List.rev items)
    | _ -> Error "expected an object"

end

module EsyManifest = struct

  type buildType =
    | InSource
    | OutOfSource
    | JBuilderLike
    [@@deriving show]

  let buildType_of_yojson = function
    | `String "_build" -> Ok JBuilderLike
    | `Bool true -> Ok InSource
    | `Bool false -> Ok OutOfSource
    | _ -> Error "expected false, true or \"_build\""

  type t = {
    build: (CommandList.t [@default None]);
    install: (CommandList.t [@default None]);
    buildsInSource: (buildType [@default OutOfSource]);
    exportedEnv: (ExportedEnv.t [@default []]);
  } [@@deriving (show, of_yojson { strict = false })]
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
    esy: EsyManifest.t;
    _resolved: (string [@default "-"]);
  } [@@deriving (show, of_yojson { strict = false })]

  let ofFile path =
    try%lwt (
        let%lwt json = Io.readJsonFile path in
        Lwt.return (Some (of_yojson json))
    ) with | Unix.Unix_error (_, _, _) -> Lwt.return None

  let ofDir (path : Path.t) =
    match%lwt ofFile (let open Path in path / "esy.json") with
    | None -> ofFile (let open Path in path / "package.json")
    | manifest -> Lwt.return manifest
end

type sourceType =
  | Immutable
  | Development
  | Root
  [@@deriving show]

type t = {
  id : string;
  name : string;
  version : string;
  dependencies : dependency list;
  buildCommands : CommandList.t;
  installCommands : CommandList.t;
  buildType : EsyManifest.buildType;
  sourceType : sourceType;
  exportedEnv : ExportedEnv.t;
  sourcePath : Path.t;
}
[@@deriving show]

and dependency =
  | Dependency of t
  | PeerDependency of t
  | DevDependency of t
  | InvalidDependency of {
    packageName: string;
    reason: string;
  }
[@@deriving show]

(**
 * Fold over a package dependency graph.
 *)
let fold ~(f : ('t, 'a) DependencyGraph.folder) (pkg : t) =
  let idOf (pkg : t) = pkg.id in
  let dependenciesOf pkg =
    let filterDep = function
      | Dependency p
      | PeerDependency p -> Some p
      | _ -> None
    in
    List.map filterDep pkg.dependencies
  in
  DependencyGraph.fold ~idOf ~dependenciesOf ~f pkg
