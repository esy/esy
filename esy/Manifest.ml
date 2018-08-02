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

  let empty = None

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

  [@@@ocaml.warning "-32"]
  type script = {
    command : CommandList.Command.t;
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
    let script (json: Json.t) =
      match CommandList.of_yojson json with
      | Ok command ->
        begin match command with
        | None
        | Some [] -> Error "empty command"
        | Some [command] -> Ok {command;}
        | Some _ -> Error "multiple script commands are not supported"
        end
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
module Env = struct

  [@@@ocaml.warning "-32"]
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

  [@@@ocaml.warning "-32"]
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

  [@@@ocaml.warning "-32"]
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
  include EsyBuildPackage.BuildType

  let of_yojson = function
    | `String "_build" -> Ok JbuilderLike
    | `Bool true -> Ok InSource
    | `Bool false -> Ok OutOfSource
    | _ -> Error "expected false, true or \"_build\""
end

module SourceType = EsyBuildPackage.SourceType

module EsyReleaseConfig = struct
  type t = {
    releasedBinaries: string list;
    deleteFromBinaryRelease: (string list [@default []]);
  } [@@deriving (show, of_yojson { strict = false })]
end

module EsyManifest = struct

  type t = {
    build: (CommandList.t [@default CommandList.empty]);
    install: (CommandList.t [@default CommandList.empty]);
    buildsInSource: (BuildType.t [@default BuildType.OutOfSource]);
    exportedEnv: (ExportedEnv.t [@default []]);
    buildEnv: (Env.t [@default Env.empty]);
    sandboxEnv: (Env.t [@default Env.empty]);
    release: (EsyReleaseConfig.t option [@default None]);
  } [@@deriving (show, of_yojson { strict = false })]

  let empty = {
    build = None;
    install = None;
    buildsInSource = BuildType.OutOfSource;
    exportedEnv = [];
    sandboxEnv = Env.empty;
    buildEnv = Env.empty;
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
    let dependencies =
      manifest.dependencies
      |> Dependencies.keys
      |> List.map ~f:(fun name -> [name])
    in
    let peerDependencies =
      manifest.peerDependencies
      |> Dependencies.keys
      |> List.map ~f:(fun name -> [name])
    in
    dependencies @ peerDependencies

  let devDependencies manifest =
    manifest.devDependencies
    |> Dependencies.keys
    |> List.map ~f:(fun name -> [name])

  let optDependencies manifest =
    manifest.optDependencies
    |> Dependencies.keys
    |> List.map ~f:(fun name -> [name])

  let buildTimeDependencies manifest =
    manifest.buildTimeDependencies
    |> Dependencies.keys
    |> List.map ~f:(fun name -> [name])

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind json = Fs.readJsonFile path in
    RunAsync.ofRun (Json.parseJsonWith of_yojson json)

  let findOfDir (path : Path.t) =
    let open RunAsync.Syntax in
    let filename = Path.(path / "esy.json") in
    if%bind Fs.exists filename
    then return (Some filename)
    else 
      let filename = Path.(path / "package.json") in
      if%bind Fs.exists filename
      then return (Some filename)
      else return None

  let ofDir (path : Path.t) =
    let open RunAsync.Syntax in
    match%bind findOfDir path with
    | Some filename ->
      let%bind manifest = ofFile filename in
      return (Some (manifest, Path.Set.singleton filename))
    | None -> return None

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

module Opam : sig
  type t

  type commands =
    | Commands of OpamTypes.command list
    | OverridenCommands of CommandList.t

  val opamName : t -> string

  val name : t -> string
  val version : t -> string

  val sourceType : t -> SourceType.t
  val buildType : t -> BuildType.t

  val buildCommands : t -> commands
  val installCommands : t -> commands
  val exportedEnv : t -> ExportedEnv.t

  val dependencies : t -> string list list
  val optDependencies : t -> string list list

  val ofDirAsInstalled : Path.t -> (t * Path.Set.t) option RunAsync.t
  val ofDirAsAggregatedRoot : Path.t -> (t * Path.Set.t) option RunAsync.t

  val patches : t -> (OpamTypes.basename * OpamTypes.filter option) list
  val substs : t -> OpamTypes.basename list

  val hasMultipleOpamFiles : t -> bool

end = struct
  type t =
    | Installed of {
        opam : OpamFile.OPAM.t;
        override : OpamOverride.t option;
      }
    | AggregatedRoot of (string * OpamFile.OPAM.t) list

  and commands =
    | Commands of OpamTypes.command list
    | OverridenCommands of CommandList.t

  let hasMultipleOpamFiles = function
    | Installed _ -> false
    | AggregatedRoot ([] | [_]) -> false
    | AggregatedRoot _ -> true

  let opamName = function
    | Installed {opam;_} ->
      let name = OpamFile.OPAM.name opam in
      OpamPackage.Name.to_string name
    | AggregatedRoot _ -> "root"

  let name manifest =
    "@opam/" ^ (opamName manifest)

  let version = function
    | Installed {opam;_} ->
      let version = OpamFile.OPAM.version opam in
      OpamPackage.Version.to_string version
    | AggregatedRoot _ -> "dev"

  let sourceType = function
    | Installed _ -> SourceType.Immutable
    | AggregatedRoot _ -> SourceType.Transient

  let buildType = function
    | Installed _ -> BuildType.InSource
    | AggregatedRoot _ -> BuildType.Unsafe

  let buildCommands = function
    | Installed manifest ->
      begin match manifest.override with
      | Some {OpamOverride. build = Some build; _} ->
        OverridenCommands build
      | Some {OpamOverride. build = None; _}
      | None ->
        Commands (OpamFile.OPAM.build manifest.opam)
      end
    | AggregatedRoot [_name, opam] ->
      Commands (OpamFile.OPAM.build opam)
    | AggregatedRoot _ ->
      Commands []

  let installCommands = function
    | Installed manifest ->
      begin match manifest.override with
      | Some {OpamOverride. install = Some install; _} ->
        OverridenCommands install
      | Some {OpamOverride. install = None; _}
      | None ->
        Commands (OpamFile.OPAM.install manifest.opam)
      end
    | AggregatedRoot [_name, opam] ->
      Commands (OpamFile.OPAM.install opam)
    | AggregatedRoot _ ->
      Commands []

  let patches = function
    | Installed manifest -> OpamFile.OPAM.patches manifest.opam
    | AggregatedRoot _ -> []

  let substs = function
    | Installed manifest -> OpamFile.OPAM.substs manifest.opam
    | AggregatedRoot _ -> []

  let exportedEnv = function
    | Installed manifest ->
      begin match manifest.override with
      | Some {OpamOverride. exportedEnv;_} -> exportedEnv
      | None -> ExportedEnv.empty
      end
    | AggregatedRoot _ -> ExportedEnv.empty

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
    let cnf = OpamFormula.to_cnf formula in
    let f atom =
      let name, _ = atom in
      let name = OpamPackage.Name.to_string name in
      "@opam/" ^ name
    in
    List.map ~f:(List.map ~f) cnf

  let dependencies manifest =
    let dependsOfOpam opam =
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
      let dependencies = ["ocaml"]::["@esy-ocaml/substs"]::dependencies in

      dependencies
    in
    match manifest with
    | Installed {opam; override} ->
      let dependencies = dependsOfOpam opam in
      begin
      match override with
      | Some {OpamOverride. dependencies = extraDependencies; _} ->
        let extraDependencies =
          extraDependencies
          |> StringMap.keys
          |> List.map ~f:(fun name -> [name])
        in
        List.append dependencies extraDependencies
      | None -> dependencies
      end
    | AggregatedRoot opams ->
      let namesPresent =
        let f names (name, _) = StringSet.add ("@opam/" ^ name) names in
        List.fold_left ~f ~init:StringSet.empty opams
      in
      let f dependencies (_name, opam) =
        let update = dependsOfOpam opam in
        let update =
          let f name = not (StringSet.mem name namesPresent) in
          List.map ~f:(List.filter ~f) update
        in
        let update =
          let f = function | [] -> false | _ -> true in
          List.filter ~f update
        in
        dependencies @ update
      in
      List.fold_left ~f ~init:[] opams

  let optDependencies manifest =
    match manifest with
    | Installed {opam;_} ->
      let dependencies =
        let f = OpamFile.OPAM.depopts opam in
        let dependencies =
          listPackageNamesOfFormula
            ~build:true ~test:false ~post:true ~doc:false ~dev:false
            f
        in
        match dependencies with
        | [] -> []
        | [single] -> List.map ~f:(fun name -> [name]) single
        | _multi ->
          (** apparently depopts has a different structure than depends in opam,
           * it's always a single list of packages in cnf
           * TODO: cleanup this mess
           *)
          assert false
      in
      dependencies
    | AggregatedRoot _ -> []

  let ofDirAsInstalled (path : Path.t) =
    let open RunAsync.Syntax in
    let filename = Path.(path / "_esy" / "opam") in
    let overrideFilename = Path.(path / "_esy" / "override.json") in
    if%bind Fs.exists filename
    then
      let%bind opam =
        let%bind data = Fs.readFile filename in
        let filename = OpamFile.make (OpamFilename.of_string (Path.toString filename)) in
        return (OpamFile.OPAM.read_from_string ~filename data)
      in
      let%bind manifest =
        if%bind Fs.exists overrideFilename
        then
          let%bind override = OpamOverride.ofFile overrideFilename in
          return (Installed {opam; override = Some override})
        else
          return (Installed {opam; override = None})
      in
      return (Some (manifest, Path.Set.singleton filename))
    else
      return None

  let ofDirAsAggregatedRoot (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind filenames = Fs.listDir path in
    let paths =
      filenames
      |> List.map ~f:(fun name -> Path.(path / name))
      |> List.filter ~f:(fun path ->
          Path.has_ext ".opam" path || Path.basename path = "opam")
    in
    let%bind opams =
      paths
      |> List.map ~f:(fun path ->
        let%bind data = Fs.readFile path in
        let opam = OpamFile.OPAM.read_from_string data in
        let name = Path.(path |> rem_ext |> basename) in
        return (name, opam))
      |> RunAsync.List.joinAll
    in
    return (Some (AggregatedRoot opams, Path.Set.of_list paths))

end

type t =
  | Esy of Esy.t
  | Opam of Opam.t

let ofDir ?(asRoot=false) (path : Path.t) =

  let relative p =
    match Path.relativize ~root:path p with
    | Some p -> p
    | None -> p
  in

  let ppPaths fmt paths =
    let paths = Path.Set.map relative paths in
    let pp = Path.Set.pp ~sep:(Fmt.unit ", ") Path.pp in
    pp fmt paths
  in

  let open RunAsync.Syntax in
  match%bind Esy.ofDir path with
  | Some (manifest, paths) ->
    let%lwt () =
      if asRoot
      then Logs_lwt.app (fun m -> m "found esy manifests: %a" ppPaths paths)
      else Lwt.return ()
    in
    return (Some (Esy manifest, paths))
  | None ->
    let opam =
      if asRoot
      then Opam.ofDirAsAggregatedRoot path
      else Opam.ofDirAsInstalled path
    in
    begin match%bind opam with
    | Some (manifest, paths) ->
      let%lwt () =
        if asRoot
        then (
          Logs_lwt.app (fun m -> m "found opam manifests: %a" ppPaths paths);%lwt
          if Opam.hasMultipleOpamFiles manifest
          then Logs_lwt.warn (fun m -> m "build commands from opam files won't be executed")
          else Lwt.return ()
        ) else Lwt.return ()
      in
      return (Some (Opam manifest, paths))
    | None -> return None
    end

let dirHasManifest (path : Path.t) =
  let open RunAsync.Syntax in
  let%bind names = Fs.listDir path in
  let f = function
    | "esy.json" | "package.json" | "opam" -> true
    | name -> Path.(name |> v |> has_ext ".opam")
  in
  return (List.exists ~f names)
