module String = Astring.String

[@@@ocaml.warning "-32"]
type 'a disj = 'a list [@@deriving ord]
[@@@ocaml.warning "-32"]
type 'a conj = 'a list [@@deriving ord]

let isOpamPackageName name =
  match String.cut ~sep:"/" name with
  | Some ("@opam", _) -> true
  | _ -> false

module File = struct
  [@@@ocaml.warning "-32"]
  type t = {
    name : string;
    content : string;
    (* file, permissions add 0o644 default for backward compat. *)
    perm : (int [@default 0o644]);
  } [@@deriving yojson, show, ord]

  let readOfPath ~prefixPath ~filePath =
      let open RunAsync.Syntax in
      let p = Path.append prefixPath filePath in
      let%bind content = Fs.readFile p
      and stat = Fs.stat p in
      let content = System.Environment.normalizeNewLines content in
      let perm = stat.Unix.st_perm in
      let name = Path.showNormalized filePath in
      return {name; content; perm}

  let writeToDir ~destinationDir file =
      let open RunAsync.Syntax in
      let {name; content; perm} = file in
      let dest = Path.append destinationDir (Fpath.v name) in
      let dirname = Path.parent dest in
      let%bind () = Fs.createDir dirname in
      let content =
          if String.get content (String.length content - 1) == '\n'
          then content
          else content ^ "\n"
      in
      let%bind () = Fs.writeFile ~perm:perm ~data:content dest in
      return()
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

module Resolution = struct

  module BuildType = struct
    include EsyLib.BuildType
    include EsyLib.BuildType.AsInPackageJson
  end

  type t = {
    name : string;
    resolution : resolution;
  }
  [@@deriving ord, show]

  and resolution =
    | Version of Version.t
    | SourceOverride of {source : Source.t; override : Json.t}

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
    let resolution = Yojson.Safe.to_string (resolution_to_yojson resolution) in
    name ^ resolution |> Digest.string |> Digest.to_hex

  let show ({name; resolution;} as r) =
    let resolution =
      match resolution with
      | Version version -> Version.show version
      | SourceOverride { source; override = _; } ->
        Source.show source ^ "@" ^ digest r
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
    let f _ resolution hash = Digest.string (hash ^ Resolution.digest resolution) in
    StringMap.fold f resolutions ""

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
          match String.cut ~sep:"/" name with
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

module Override = struct

  type t =
    | OfDist of (Dist.t * Json.t option)
    | OfJson of Json.t

  type build = {
    buildType : BuildType.t option [@default None];
    build : CommandList.t option [@default None];
    install : CommandList.t option [@default None];
    exportedEnv: ExportedEnv.t option [@default None];
    exportedEnvOverride: ExportedEnvOverride.t option [@default None];
    buildEnv: Env.t option [@default None];
    buildEnvOverride: EnvOverride.t option [@default None];
  } [@@deriving show, of_yojson {strict = false}]

  type install = {
    dependencies : NpmFormulaOverride.t option [@default None];
    devDependencies : NpmFormulaOverride.t option [@default None];
    resolutions : Resolution.resolution StringMap.t option [@default None];
  } [@@deriving of_yojson {strict = false}]

  type manifest = {
    override: Json.t;
  } [@@deriving of_yojson {strict = false}]

  let ofJson json = OfJson json
  let ofDist ?json dist = OfDist (dist, json)

  let to_yojson override =
    match override with
    | OfJson json -> json
    | OfDist (dist, _) -> Dist.to_yojson dist

  let of_yojson json =
    let open Result.Syntax in
    match json with
    | `String _ ->
      let%map dist = Dist.of_yojson json in
      OfDist (dist, None)
    | json ->
      return (OfJson json)

  let files ~cfg override =
    let open RunAsync.Syntax in
    match override with
    | OfJson _ -> return []
    | OfDist (dist, _) ->
      let%bind path = DistStorage.fetchAndUnpackToCache ~cfg dist in
      let filesPath = Path.(path / "files") in
      if%bind Fs.exists filesPath
      then
        let%bind files = Fs.listDir filesPath in
        let f filename =
          File.readOfPath
            ~prefixPath:filesPath
            ~filePath:Path.(filesPath / filename)
        in
        RunAsync.List.mapAndJoin ~f files
      else
        return []

  let fetch ~cfg override =
    let open RunAsync.Syntax in
    match override with
    | OfJson json -> return json
    | OfDist (_dist, Some json) -> return json
    | OfDist (dist, None) ->
      let%bind path =
        match dist with
        | Dist.LocalPath info -> return info.path
        | dist -> DistStorage.fetchAndUnpackToCache ~cfg dist
      in
      let filename =
        match Dist.manifest dist with
        | Some ManifestSpec.One (Esy, filename) -> filename
        | Some ManifestSpec.One (Opam, _) -> failwith "cannot read override from Opam"
        | Some ManifestSpec.ManyOpam -> failwith "cannot read override from ManyOpam"
        | None -> "package.json"
      in
      let%bind json = Fs.readJsonFile Path.(path / filename) in
      let%bind manifest = RunAsync.ofStringError (manifest_of_yojson json) in
      return manifest.override

  let install ~cfg override =
    let open RunAsync.Syntax in
    let%bind json = fetch ~cfg override in
    let%bind override = RunAsync.ofStringError (install_of_yojson json) in
    return (Some override)

  let build ~cfg override =
    let open RunAsync.Syntax in
    let%bind json = fetch ~cfg override in
    let%bind override = RunAsync.ofStringError (build_of_yojson json) in
    return (Some override)

end

module Overrides = struct
  type t =
    Override.t list
    [@@deriving yojson]

  let isEmpty = function
    | [] -> true
    | _ -> false

  let empty = []

  let add override overrides =
    override::overrides

  let addMany newOverrides overrides =
    newOverrides @ overrides

  let merge newOverrides overrides =
    newOverrides @ overrides

  let toList overrides = List.rev overrides

  let fold' ~f ~init overrides =
    RunAsync.List.foldLeft ~f ~init (List.rev overrides)

  let files ~cfg overrides =
    let open RunAsync.Syntax in
    let f files override =
      let%bind filesOfOverride = Override.files ~cfg override in
      return (filesOfOverride @ files)
    in
    fold' ~f ~init:[] overrides

  let foldWithBuildOverrides ~cfg ~f ~init overrides =
    let open RunAsync.Syntax in
    let f v override =
      match%bind Override.build ~cfg override with
      | Some override -> return (f v override)
      | None -> return v
    in
    fold' ~f ~init overrides

  let foldWithInstallOverrides ~cfg ~f ~init overrides =
    let open RunAsync.Syntax in
    let f v override =
      match%bind Override.install ~cfg override with
      | Some override -> return (f v override)
      | None -> return v
    in
    fold' ~f ~init overrides

  let apply overrides f init =
    List.fold_left ~f ~init (List.rev overrides)

end

module Dep = struct
  type t = {
    name : string;
    req : req;
  } [@@deriving ord]

  and req =
    | Npm of SemverVersion.Constraint.t
    | NpmDistTag of string
    | Opam of OpamPackageVersion.Constraint.t
    | Source of SourceSpec.t

  let pp fmt {name; req;} =
    let ppReq fmt = function
      | Npm c -> SemverVersion.Constraint.pp fmt c
      | NpmDistTag tag -> Fmt.string fmt tag
      | Opam c -> OpamPackageVersion.Constraint.pp fmt c
      | Source src -> SourceSpec.pp fmt src
    in
    Fmt.pf fmt "%s@%a" name ppReq req

end

module Dependencies = struct

  type t =
    | OpamFormula of Dep.t disj conj
    | NpmFormula of NpmFormula.t
    [@@deriving ord]

  let toApproximateRequests = function
    | NpmFormula reqs -> reqs
    | OpamFormula reqs ->
      let reqs =
        let f reqs deps =
          let f reqs (dep : Dep.t) =
            let spec =
              match dep.req with
              | Dep.Npm _ -> VersionSpec.Npm [[SemverVersion.Constraint.ANY]]
              | Dep.NpmDistTag tag -> VersionSpec.NpmDistTag tag
              | Dep.Opam _ -> VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]]
              | Dep.Source srcSpec -> VersionSpec.Source srcSpec
            in
            Req.Set.add (Req.make ~name:dep.name ~spec) reqs
          in
          List.fold_left ~f ~init:reqs deps
        in
        List.fold_left ~f ~init:Req.Set.empty reqs
      in
      Req.Set.elements reqs

  let pp fmt deps =
    match deps with
    | OpamFormula deps ->
      let ppDisj fmt disj =
        match disj with
        | [] -> Fmt.unit "true" fmt ()
        | [dep] -> Dep.pp fmt dep
        | deps -> Fmt.pf fmt "(%a)" Fmt.(list ~sep:(unit " || ") Dep.pp) deps
      in
      Fmt.pf fmt "@[<h>%a@]" Fmt.(list ~sep:(unit " && ") ppDisj) deps
    | NpmFormula deps -> NpmFormula.pp fmt deps

  let show deps =
    Format.asprintf "%a" pp deps

  let filterDependenciesByName ~name deps =
    let findInNpmFormula reqs =
      let f req = req.Req.name = name in
      List.filter ~f reqs
    in
    let findInOpamFormula cnf =
      let f disj =
        let f dep = dep.Dep.name = name in
        List.exists ~f disj
      in
      List.filter ~f cnf
    in
    match deps with
    | NpmFormula f -> NpmFormula (findInNpmFormula f)
    | OpamFormula f -> OpamFormula (findInOpamFormula f)
end

module Opam = struct

  module OpamFile = struct
    type t = OpamFile.OPAM.t
    let pp fmt opam = Fmt.string fmt (OpamFile.OPAM.write_to_string opam)
    let to_yojson opam = `String (OpamFile.OPAM.write_to_string opam)
    let of_yojson = function
      | `String s -> Ok (OpamFile.OPAM.read_from_string s)
      | _ -> Error "expected string"
  end

  module OpamName = struct
    type t = OpamPackage.Name.t
    let pp fmt name = Fmt.string fmt (OpamPackage.Name.to_string name)
    let to_yojson name = `String (OpamPackage.Name.to_string name)
    let of_yojson = function
      | `String name -> Ok (OpamPackage.Name.of_string name)
      | _ -> Error "expected string"
  end

  module OpamPackageVersion = struct
    type t = OpamPackage.Version.t
    let pp fmt name = Fmt.string fmt (OpamPackage.Version.to_string name)
    let to_yojson name = `String (OpamPackage.Version.to_string name)
    let of_yojson = function
      | `String name -> Ok (OpamPackage.Version.of_string name)
      | _ -> Error "expected string"
  end

  type t = {
    name : OpamName.t;
    version : OpamPackageVersion.t;
    opam : OpamFile.t;
    files : unit -> File.t list RunAsync.t;
  }
end

type t = {
  name : string;
  version : Version.t;
  originalVersion : Version.t option;
  originalName : string option;
  source : source;
  overrides : Overrides.t;
  dependencies: Dependencies.t;
  devDependencies: Dependencies.t;
  optDependencies: StringSet.t;
  resolutions : Resolutions.t;
  kind : kind;
}

and source =
  | Link of {
      path : Path.t;
      manifest : ManifestSpec.t option;
    }
  | Install of {
      source : Source.t * Source.t list;
      opam : Opam.t option;
    }

and kind =
  | Esy
  | Npm

let pp fmt pkg =
  Fmt.pf fmt "%s@%a" pkg.name Version.pp pkg.version

let compare pkga pkgb =
  let name = String.compare pkga.name pkgb.name in
  if name = 0
  then Version.compare pkga.version pkgb.version
  else name

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)
