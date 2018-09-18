module Command = struct

  [@@@ocaml.warning "-32"]
  type t =
    | Parsed of string list
    | Unparsed of string
    [@@deriving show, ord]

  let of_yojson (json : Json.t) =
    match json with
    | `String command -> Ok (Unparsed command)
    | `List command ->
      begin match Json.Parse.(list string (`List command)) with
      | Ok args -> Ok (Parsed args)
      | Error err -> Error err
      end
    | _ -> Error "expected either a string or an array of strings"

  let to_yojson v =
    match v with
    | Parsed args -> `List (List.map ~f:(fun arg -> `String arg) args)
    | Unparsed line -> `String line

end

module CommandList = struct

  [@@@ocaml.warning "-32"]
  type t =
    Command.t list
    [@@deriving show, ord]

  let empty = []

  let of_yojson (json : Json.t) =
    let open Result.Syntax in
    match json with
    | `Null -> return []
    | `List commands ->
      Json.Parse.list Command.of_yojson (`List commands)
    | `String command ->
      let%bind command = Command.of_yojson (`String command) in
      return [command]
    | _ -> Error "expected either a null, a string or an array"

  let to_yojson commands = `List (List.map ~f:Command.to_yojson commands)

end

module Env = struct

  [@@@ocaml.warning "-32"]
  type item = {
    name : string;
    value : string;
  }
  [@@deriving show, ord]

  type t =
    item StringMap.t
    [@@deriving ord]

  let empty = StringMap.empty

  let item_of_yojson name json =
    match json with
    | `String value -> Ok {name; value;}
    | _ -> Error "expected string"

  let of_yojson =
    let open Result.Syntax in
    function
    | `Assoc items ->
      let f items (name, json) =
        let%bind item = item_of_yojson name json in
        return (StringMap.add name item items)
      in
      Result.List.foldLeft ~f ~init:StringMap.empty items
    | _ -> Error "expected object"

  let item_to_yojson {value;_} = `String value

  let to_yojson env =
    let items =
      let f (name, item) = name, item_to_yojson item in
      List.map ~f (StringMap.bindings env)
    in
    `Assoc items

  let pp =
    let ppItem fmt (name, {value;_}) =
      Fmt.pf fmt "%s: %s" name value
    in
    StringMap.pp ~sep:(Fmt.unit ", ") ppItem

  let show env = Format.asprintf "%a" pp env
end

module EnvOverride = struct
  type t = Env.item StringMap.Override.t [@@deriving ord]
  let of_yojson = StringMap.Override.of_yojson Env.item_of_yojson
  let to_yojson = StringMap.Override.to_yojson Env.item_to_yojson
end

module ExportedEnv = struct

  [@@@ocaml.warning "-32"]
  type scope =
    | Local
    | Global
    [@@deriving show, ord]

  let scope_of_yojson = function
    | `String "global" -> Ok Global
    | `String "local" -> Ok Local
    | _ -> Error "expected either \"local\" or \"global\""

  let scope_to_yojson = function
    | Local -> `String "local"
    | Global -> `String "global"

  module Item = struct
    type t = {
      value : string [@key "val"];
      scope : (scope [@default Local]);
      exclusive : (bool [@default false]);
    }
    [@@deriving yojson]
  end

  [@@@ocaml.warning "-32"]
  type item = {
    name : string;
    value : string;
    scope : scope;
    exclusive : bool;
  }
  [@@deriving show, ord]

  type t = item StringMap.t
    [@@deriving ord]

  let empty = StringMap.empty

  let item_of_yojson name json =
    let open Result.Syntax in
    let%bind {Item. value; scope; exclusive} = Item.of_yojson json in
    return ({name; value; scope; exclusive})

  let of_yojson = function
    | `Assoc items ->
      let open Result.Syntax in
      let f items (name, json) =
        let%bind item = item_of_yojson name json in
        return (StringMap.add name item items)
      in
      Result.List.foldLeft ~f ~init:StringMap.empty items
    | _ -> Error "expected an object"

  let item_to_yojson item =
    `Assoc [
      "val", `String item.value;
      "scope", scope_to_yojson item.scope;
      "exclusive", `Bool item.exclusive;
    ]

  let to_yojson env =
    let items =
      let f (name, item) = name, item_to_yojson item in
      List.map ~f (StringMap.bindings env)
    in
    `Assoc items

  let pp =
    let ppItem fmt (name, item) =
      Fmt.pf fmt "%s: %a" name pp_item item
    in
    StringMap.pp ~sep:(Fmt.unit ", ") ppItem

  let show env = Format.asprintf "%a" pp env

end

module ExportedEnvOverride = struct

  type t =
    ExportedEnv.item StringMap.Override.t
    [@@deriving ord]

  let of_yojson = StringMap.Override.of_yojson ExportedEnv.item_of_yojson
  let to_yojson = StringMap.Override.to_yojson ExportedEnv.item_to_yojson

end

module Dependencies = struct

  type t = Req.t list [@@deriving ord]

  let empty = []

  let pp fmt deps =
    Fmt.pf fmt "@[<hov>[@;%a@;]@]" (Fmt.list ~sep:(Fmt.unit ", ") Req.pp) deps

  let of_yojson json =
    let open Result.Syntax in
    let%bind items = Json.Parse.assoc json in
    let f deps (name, json) =
      let%bind spec = Json.Parse.string json in
      let%bind req = Req.parse (name ^ "@" ^ spec) in
      return (req::deps)
    in
    Result.List.foldLeft ~f ~init:empty items

  let to_yojson (reqs : t) =
    let items =
      let f (req : Req.t) = (req.name, VersionSpec.to_yojson req.spec) in
      List.map ~f reqs
    in
    `Assoc items

  let override deps update =
    let map =
      let f map (req : Req.t) = StringMap.add req.name req map in
      let map = StringMap.empty in
      let map = List.fold_left ~f ~init:map deps in
      let map = List.fold_left ~f ~init:map update in
      map
    in
    StringMap.values map

  let find ~name reqs =
    let f (req : Req.t) = req.name = name in
    List.find_opt ~f reqs
end



module EsyPackageJson = struct
  type t = {
    _dependenciesForNewEsyInstaller : (Dependencies.t option [@default None]);
  } [@@deriving of_yojson { strict = false }]
end

type t = {
  name : (string option [@default None]);
  version : (SemverVersion.Version.t option [@default None]);
  dependencies : (Dependencies.t [@default Dependencies.empty]);
  devDependencies : (Dependencies.t [@default Dependencies.empty]);
  esy : (EsyPackageJson.t option [@default None]);
} [@@deriving of_yojson { strict = false }]

let findInDir (path : Path.t) =
  let open RunAsync.Syntax in
  let esyJson = Path.(path / "esy.json") in
  let packageJson = Path.(path / "package.json") in
  if%bind Fs.exists esyJson
  then return (Some esyJson)
  else if%bind Fs.exists packageJson
  then return (Some packageJson)
  else return None

let ofFile path =
  let open RunAsync.Syntax in
  let%bind json = Fs.readJsonFile path in
  RunAsync.ofRun (Json.parseJsonWith of_yojson json)

let ofDir path =
  let open RunAsync.Syntax in
  match%bind findInDir path with
  | Some filename ->
    let%bind json = Fs.readJsonFile filename in
    RunAsync.ofRun (Json.parseJsonWith of_yojson json)
  | None -> error "no package.json (or esy.json) found"
