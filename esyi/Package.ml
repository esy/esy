module String = Astring.String

[@@@ocaml.warning "-32"]
type 'a disj = 'a list
[@@@ocaml.warning "-32"]
type 'a conj = 'a list

module Override = struct
  module BuildType = struct
    include EsyLib.BuildType
    include EsyLib.BuildType.AsInPackageJson
  end

  type t = {
    buildType : BuildType.t option [@default None] [@key "buildsInSource"];
    build : PackageJson.CommandList.t option [@default None];
    install : PackageJson.CommandList.t option [@default None];
    exportedEnv: PackageJson.ExportedEnv.t option [@default None];
    exportedEnvOverride: PackageJson.ExportedEnvOverride.t option [@default None];
    buildEnv: PackageJson.Env.t option [@default None];
    buildEnvOverride: PackageJson.EnvOverride.t option [@default None];
    dependencies : PackageJson.Dependencies.t option [@default None];
  } [@@deriving yojson, ord]
end

module Resolution = struct

  type t = {
    name : string;
    resolution : resolution;
  }
  [@@deriving ord]

  and resolution =
    | Version of Version.t
    | SourceOverride of {source : Source.t; override : Override.t}

  let resolution_to_yojson resolution =
    match resolution with
    | Version v -> `String (Version.show v)
    | SourceOverride {source; override} ->
      `Assoc [
        "source", Source.to_yojson source;
        "override", Override.to_yojson override;
      ]

  let resolution_of_yojson json =
    let open Result.Syntax in
    match json with
    | `String v ->
      let%bind version = Version.parse v in
      return (Version version)
    | `Assoc _ ->
      let%bind source = Json.Parse.fieldWith ~name:"source" Source.of_yojson json in
      let%bind override = Json.Parse.fieldWith ~name:"override" Override.of_yojson json in
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

module Dep = struct
  type t = {
    name : string;
    req : req;
  }

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
    | NpmFormula of Req.t conj

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
      Fmt.pf fmt "@[<h>[@;%a@;]@]" Fmt.(list ~sep:(unit " && ") ppDisj) deps
    | NpmFormula deps -> PackageJson.Dependencies.pp fmt deps

  let show deps =
    Format.asprintf "%a" pp deps
end

module File = struct
  [@@@ocaml.warning "-32"]
  type t = {
    name : Path.t;
    content : string;
    (* file, permissions add 0o644 default for backward compat. *)
    perm : (int [@default 0o644]);
  } [@@deriving yojson, show, ord]
end

module OpamOverride = struct
  module Opam = struct
    [@@@ocaml.warning "-32"]
    type t = {
      source: (source option [@default None]);
      files: (File.t list [@default []]);
    } [@@deriving yojson, ord, show]

    and source = {
      url: string;
      checksum: string;
    }

    let empty = {source = None; files = [];}

  end

  type t = {
    build: (PackageJson.CommandList.t option [@default None]);
    install: (PackageJson.CommandList.t option [@default None]);
    dependencies: (PackageJson.Dependencies.t [@default PackageJson.Dependencies.empty]);
    peerDependencies: (PackageJson.Dependencies.t [@default PackageJson.Dependencies.empty]) ;
    exportedEnv: (PackageJson.ExportedEnv.t [@default PackageJson.ExportedEnv.empty]);
    opam: (Opam.t [@default Opam.empty]);
  } [@@deriving yojson, ord, show]

  let empty =
    {
      build = None;
      install = None;
      dependencies = PackageJson.Dependencies.empty;
      peerDependencies = PackageJson.Dependencies.empty;
      exportedEnv = PackageJson.ExportedEnv.empty;
      opam = Opam.empty;
    }
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
    override : OpamOverride.t;
  }
  [@@deriving show]
end

type t = {
  name : string;
  version : Version.t;
  originalVersion : Version.t option;
  source : Source.t * Source.t list;
  override : Override.t list;
  dependencies: Dependencies.t;
  devDependencies: Dependencies.t;
  opam : Opam.t option;
  kind : kind;
}

and kind =
  | Esy
  | Npm

let isOpamPackageName name =
  match String.cut ~sep:"/" name with
  | Some ("@opam", _) -> true
  | _ -> false

let pp fmt pkg =
  Fmt.pf fmt "%s@%a" pkg.name Version.pp pkg.version

let compare pkga pkgb =
  let name = String.compare pkga.name pkgb.name in
  if name = 0
  then Version.compare pkga.version pkgb.version
  else name

let ofPackageJson ~name ~version ~source (pkgJson : PackageJson.t) =
  let originalVersion =
    match pkgJson.version with
    | Some version -> Some (Version.Npm version)
    | None -> None
  in
  let dependencies =
    match pkgJson.esy with
    | None
    | Some {PackageJson.EsyPackageJson. _dependenciesForNewEsyInstaller= None} ->
      pkgJson.dependencies
    | Some {PackageJson.EsyPackageJson. _dependenciesForNewEsyInstaller= Some dependencies} ->
      dependencies
  in
  {
    name;
    version;
    originalVersion;
    dependencies = Dependencies.NpmFormula dependencies;
    devDependencies = Dependencies.NpmFormula pkgJson.devDependencies;
    source = source, [];
    override = [];
    opam = None;
    kind = if Option.isSome pkgJson.esy then Esy else Npm;
  }

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)
