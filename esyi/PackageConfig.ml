module Resolution = struct

  [@@@ocaml.warning "-32"]
  type t = {
    name : string;
    resolution : resolution;
  }
  [@@deriving ord, show]

  and resolution =
    | Version of Version.t
    | SourceOverride of {source : Source.t; override : Json.t}
  [@@@ocaml.warning "+32"]

  let resolution_to_yojson resolution =
    match resolution with
    | Version v -> `String (Version.show v)
    | SourceOverride {source; override} ->
      `Assoc [
        "source", Source.to_yojson source;
        "override", override;
      ]

  let resolution_of_yojson json =
    let open Result.Syntax in
    match json with
    | `String v ->
      let%bind version = Version.parse v in
      return (Version version)
    | `Assoc _ ->
      let%bind source = Json.Decode.fieldWith ~name:"source" Source.relaxed_of_yojson json in
      let%bind override = Json.Decode.fieldWith ~name:"override" Json.of_yojson json in
      return (SourceOverride {source; override;})
    | _ -> Error "expected string or object"

  let digest {name; resolution} =
    Digestv.(
      empty
      |> add (string name)
      |> add (json (resolution_to_yojson resolution))
    )

  let show ({name; resolution;} as r) =
    let resolution =
      match resolution with
      | Version version -> Version.show version
      | SourceOverride { source; override = _; } ->
        Source.show source ^ "@" ^ (Digestv.toHex (digest r))
    in
    name ^ "@" ^ resolution

  let pp fmt r = Fmt.string fmt (show r)

end

module Resolutions = struct
  type t = Resolution.t StringMap.t

  let empty = StringMap.empty

  let find resolutions name =
    StringMap.find_opt name resolutions

  let add name resolution resolutions =
    StringMap.add name {Resolution.name; resolution} resolutions

  let entries = StringMap.values

  let digest resolutions =
    let f _ resolution digest = Digestv.(digest + Resolution.digest resolution) in
    StringMap.fold f resolutions Digestv.empty

  let to_yojson v =
    let items =
      let f name {Resolution. resolution; _} items =
        (name, Resolution.resolution_to_yojson resolution)::items
      in
      StringMap.fold f v []
    in
    `Assoc items

  let of_yojson =
    let open Result.Syntax in
    let parseKey k =
      match PackagePath.parse k with
      | Ok ((_path, name)) -> Ok name
      | Error err -> Error err
    in
    let parseValue name json =
      match json with
      | `String v ->
        let%bind version =
          match Astring.String.cut ~sep:"/" name with
          | Some ("@opam", _) -> Version.parse ~tryAsOpam:true v
          | _ -> Version.parse v
        in
        return {Resolution. name; resolution = Resolution.Version version;}
      | `Assoc _ ->
        let%bind resolution = Resolution.resolution_of_yojson json in
        return {Resolution. name; resolution;}
      | _ -> Error "expected string"
    in
    function
    | `Assoc items ->
      let f res (key, json) =
        let%bind key = parseKey key in
        let%bind value = parseValue key json in
        Ok (StringMap.add key value res)
      in
      Result.List.foldLeft ~f ~init:empty items
    | _ -> Error "expected object"

end

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
      begin match Json.Decode.(list string (`List command)) with
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
      Json.Decode.list Command.of_yojson (`List commands)
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
  type t = Env.item StringMap.Override.t [@@deriving ord, show]
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
    [@@deriving ord, show]

  let of_yojson = StringMap.Override.of_yojson ExportedEnv.item_of_yojson
  let to_yojson = StringMap.Override.to_yojson ExportedEnv.item_to_yojson

end

module NpmFormula = struct

  type t = Req.t list [@@deriving ord]

  let empty = []

  let pp fmt deps =
    Fmt.pf fmt "@[<h>%a@]" (Fmt.list ~sep:(Fmt.unit ", ") Req.pp) deps

  let of_yojson json =
    let open Result.Syntax in
    let%bind items = Json.Decode.assoc json in
    let f deps (name, json) =
      let%bind spec = Json.Decode.string json in
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

module NpmFormulaOverride = struct
  type t = Req.t StringMap.Override.t [@@deriving ord, show]

  let of_yojson =
    let req_of_yojson name json =
      let open Result.Syntax in
      let%bind spec = Json.Decode.string json in
      Req.parse (name ^ "@" ^ spec)
    in
    StringMap.Override.of_yojson req_of_yojson

  let to_yojson =
    let req_to_yojson req =
      VersionSpec.to_yojson req.Req.spec
    in
    StringMap.Override.to_yojson req_to_yojson
end


