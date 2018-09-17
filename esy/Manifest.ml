module BuildType = struct
  include EsyLib.BuildType

  let of_yojson = function
    | `String "_build" -> Ok JbuilderLike
    | `Bool true -> Ok InSource
    | `Bool false -> Ok OutOfSource
    | _ -> Error "expected false, true or \"_build\""
end

module SandboxSpec = EsyInstall.SandboxSpec
module PackageJson = EsyInstall.PackageJson
module Source = EsyInstall.Source
module SourceType = EsyLib.SourceType
module Command = PackageJson.Command
module CommandList = PackageJson.CommandList
module ExportedEnv = PackageJson.ExportedEnv

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

  let to_yojson env =
    let items =
      let f {name; value} = name, `String value in
      List.map ~f env
    in
    `Assoc items
end

module Build = struct

  (* aliases for opam types with to_yojson implementations *)
  module OpamTypes = struct
    type filter = OpamTypes.filter

    let filter_to_yojson filter = `String (OpamFilter.to_string filter)

    type command = arg list * filter option [@@deriving to_yojson]
    and arg = simple_arg * filter option
    and simple_arg = OpamTypes.simple_arg =
      | CString of string
      | CIdent of string
  end

  type commands =
    | OpamCommands of OpamTypes.command list
    | EsyCommands of CommandList.t
    [@@deriving to_yojson]

  type patch = Path.t * OpamTypes.filter option

  let patch_to_yojson (path, filter) =
    let filter =
      match filter with
      | None -> `Null
      | Some filter -> `String (OpamFilter.to_string filter)
    in
    `Assoc ["path", Path.to_yojson path; "filter", filter]

  type t = {
    buildType : BuildType.t;
    buildCommands : commands;
    installCommands : commands;
    patches : patch list;
    substs : Path.t list;
    exportedEnv : ExportedEnv.t;
    buildEnv : Env.t;
  } [@@deriving to_yojson]

  let empty = {
    buildType = BuildType.OutOfSource;
    buildCommands = EsyCommands [];
    installCommands = EsyCommands [];
    patches = [];
    substs = [];
    exportedEnv = [];
    buildEnv = [];
  }

end

module Dependencies = struct
  type t = {
    dependencies : string list list;
    devDependencies : string list list;
    buildTimeDependencies : string list list;
    optDependencies : string list list;
  } [@@deriving show]

  let empty = {
    dependencies = [];
    devDependencies = [];
    buildTimeDependencies = [];
    optDependencies = [];
  }
end

module Release = struct
  type t = {
    releasedBinaries: string list;
    deleteFromBinaryRelease: (string list [@default []]);
  } [@@deriving (of_yojson { strict = false })]
end

module Scripts = struct

  [@@@ocaml.warning "-32"]
  type script = {
    command : Command.t;
  }
  [@@deriving (eq, ord)]

  type t =
    script StringMap.t
    [@@deriving (eq, ord)]

  let empty = StringMap.empty

  let of_yojson =
    let script (json: Json.t) =
      match CommandList.of_yojson json with
      | Ok command ->
        begin match command with
        | [] -> Error "empty command"
        | [command] -> Ok {command;}
        | _ -> Error "multiple script commands are not supported"
        end
      | Error err -> Error err
    in
    Json.Parse.stringMap script

  let find (cmd: string) (scripts: t) = StringMap.find_opt cmd scripts
end

module type MANIFEST = sig
  (**
   * Manifest.
   *
   * This can be either esy manifest (package.json/esy.json) or opam manifest but
   * this type abstracts them out.
   *)
  type t

  (** Name. *)
  val name : t -> string

  (** Version. *)
  val version : t -> string

  (** License. *)
  val license : t -> Json.t option

  (** Description. *)
  val description : t -> string option

  (**
   * Extract dependency info.
   *)
  val dependencies : t -> Dependencies.t

  (**
   * Extract build config from manifest
   *
   * Not all packages have build config defined so we return `None` in this case.
   *)
  val build : t -> Build.t option

  (**
   * Extract release config from manifest
   *
   * Not all packages have release config defined so we return `None` in this
   * case.
   *)
  val release : t -> Release.t option

  (**
   * Extract release config from manifest
   *
   * Not all packages have release config defined so we return `None` in this
   * case.
   *)
  val scripts : t -> Scripts.t Run.t

  val sandboxEnv : t -> Env.t Run.t
end

module Esy : sig
  include MANIFEST

  val ofFile : Path.t -> t RunAsync.t
end = struct

  module EsyManifest = struct

    type t = {
      build: (CommandList.t [@default CommandList.empty]);
      install: (CommandList.t [@default CommandList.empty]);
      buildsInSource: (BuildType.t [@default BuildType.OutOfSource]);
      exportedEnv: (ExportedEnv.t [@default []]);
      buildEnv: (Env.t [@default Env.empty]);
      sandboxEnv: (Env.t [@default Env.empty]);
      release: (Release.t option [@default None]);
    } [@@deriving (of_yojson { strict = false })]

  end

  module JsonManifest = struct
    type t = {
      name : (string option [@default None]);
      version : (string option [@default None]);
      description : (string option [@default None]);
      license : (Json.t option [@default None]);
      dependencies : (PackageJson.Dependencies.t [@default PackageJson.Dependencies.empty]);
      peerDependencies : (PackageJson.Dependencies.t [@default PackageJson.Dependencies.empty]);
      devDependencies : (PackageJson.Dependencies.t [@default PackageJson.Dependencies.empty]);
      optDependencies : (PackageJson.Dependencies.t [@default PackageJson.Dependencies.empty]);
      buildTimeDependencies : (PackageJson.Dependencies.t [@default PackageJson.Dependencies.empty]);
      esy: EsyManifest.t option [@default None];
    } [@@deriving (of_yojson {strict = false})]
  end

  type manifest = {
    name : string;
    version : string;
    description : string option;
    license : Json.t option;
    dependencies : PackageJson.Dependencies.t;
    peerDependencies : PackageJson.Dependencies.t;
    devDependencies : PackageJson.Dependencies.t;
    optDependencies : PackageJson.Dependencies.t;
    buildTimeDependencies : PackageJson.Dependencies.t;
    esy: EsyManifest.t option;
  }

  type t = manifest * Json.t

  let name (manifest, _) = manifest.name
  let version (manifest, _) = manifest.version
  let description (manifest, _) = manifest.description
  let license (manifest, _) = manifest.license

  let dependencies (manifest, _) =
    let names reqs = List.map ~f:(fun req -> [req.EsyInstall.Req.name]) reqs in
    let dependencies =
      let dependencies = names manifest.dependencies in
      let peerDependencies = names manifest.peerDependencies in
      dependencies @ peerDependencies
    in
    let devDependencies = names manifest.devDependencies in
    let optDependencies = names manifest.optDependencies in
    let buildTimeDependencies = names manifest.buildTimeDependencies in
    {
      Dependencies.
      dependencies;
      devDependencies;
      optDependencies;
      buildTimeDependencies
    }

  let release (m, _) =
    let open Option.Syntax in
    let%bind m = m.esy in
    let%bind c = m.EsyManifest.release in
    return c

  let scripts (_, json) =
    let open Run.Syntax in
    match json with
    | `Assoc items ->
      let f (name, _) = name = "scripts" in
      begin match List.find_opt ~f items with
      | Some (_, json) -> Run.ofStringError (Scripts.of_yojson json)
      | None -> return Scripts.empty
      end
    | _ -> return Scripts.empty

  let sandboxEnv (m, _) =
    match m.esy with
    | None -> Run.return Env.empty
    | Some m -> Run.return m.sandboxEnv

  let build (m, _) =
    let open Option.Syntax in
    let%bind esy = m.esy in
    Some {
      Build.
      buildType = esy.EsyManifest.buildsInSource;
      exportedEnv = esy.EsyManifest.exportedEnv;
      buildEnv = esy.EsyManifest.buildEnv;
      buildCommands = EsyCommands (esy.EsyManifest.build);
      installCommands = EsyCommands (esy.EsyManifest.install);
      patches = [];
      substs = [];
    }

  let ofJsonManifest (jsonManifest: JsonManifest.t) (path: Path.t) =
    let name = 
      match jsonManifest.name with
      | Some name  -> name
      | None -> Path.basename path
    in
    let version =
      match jsonManifest.version with
      | Some version  -> version
      | None -> "0.0.0"
    in
    {
      name;
      version;
      description = jsonManifest.description;
      license = jsonManifest.license;
      dependencies = jsonManifest.dependencies;
      peerDependencies = jsonManifest.peerDependencies;
      devDependencies = jsonManifest.devDependencies;
      optDependencies = jsonManifest.optDependencies;
      buildTimeDependencies = jsonManifest.buildTimeDependencies;
      esy = jsonManifest.esy;
    }

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind json = Fs.readJsonFile path in
    let%bind jsonManifest =
      RunAsync.ofRun (Json.parseJsonWith JsonManifest.of_yojson json)
    in
    let manifest = ofJsonManifest jsonManifest path in
    return (manifest, json)

end

module Opam : sig
  include MANIFEST

  val ofFiles : Path.t list -> t RunAsync.t
  val ofFile :
    ?name:string
    -> Path.t
    -> t RunAsync.t

end = struct
  type t =
    | Installed of {
        name : string option;
        opam : OpamFile.OPAM.t;
        info : EsyInstall.EsyOpamFile.t;
      }
    | AggregatedRoot of (string * OpamFile.OPAM.t) list

  let opamname = function
    | Installed {opam; _} ->
      let name = OpamFile.OPAM.name opam in
      OpamPackage.Name.to_string name
    | AggregatedRoot _ -> "root"

  let name manifest =
    match manifest with
    | Installed {name = Some name; _} -> name
    | manifest -> "@opam/" ^ (opamname manifest)

  let version = function
    | Installed {opam;_} -> (
        try OpamPackage.Version.to_string (OpamFile.OPAM.version opam)
        with _ -> "dev"
      )
    | AggregatedRoot _ -> "dev"

  let listPackageNamesOfFormula ~build ~test ~post ~doc ~dev formula =
    let formula =
      OpamFilter.filter_deps
        ~default:true ~build ~post ~test ~doc ~dev
        formula
    in
    let cnf = OpamFormula.to_cnf formula in
    let f atom =
      let name, _ = atom in
      match OpamPackage.Name.to_string name with
      | "ocaml" -> "ocaml"
      | name -> "@opam/" ^ name
    in
    List.map ~f:(List.map ~f) cnf

  let dependencies manifest =
    let dependencies =

      let dependsOfOpam opam =
        let f = OpamFile.OPAM.depends opam in
        let dependencies =
          listPackageNamesOfFormula
            ~build:true ~test:false ~post:true ~doc:false ~dev:false
            f
        in
        let dependencies = ["ocaml"]::["@esy-ocaml/substs"]::dependencies in

        dependencies
      in
      match manifest with
      | Installed {opam; info; name = _} ->
        let dependencies = dependsOfOpam opam in
        begin
        match info.override with
        | Some {EsyInstall.Package.OpamOverride. dependencies = extraDependencies; _} ->
          let extraDependencies =
            extraDependencies
            |> List.map ~f:(fun req -> [req.EsyInstall.Req.name])
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
    in

    let optDependencies =
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
    in
    {
      Dependencies.
      dependencies;
      buildTimeDependencies = [];
      devDependencies = [];
      optDependencies;
    }

  let ofFile ?name (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind opam =
      let%bind data = Fs.readFile path in
      let filename = OpamFile.make (OpamFilename.of_string (Path.toString path)) in
      let opam = OpamFile.OPAM.read_from_string ~filename data in
      let opam = OpamFormatUpgrade.opam_file ~filename opam in
      return opam
    in
    let%bind info =
      let esyOpamPath = Path.(parent path / "esy-opam.json") in
      if%bind Fs.exists esyOpamPath
      then EsyInstall.EsyOpamFile.ofFile esyOpamPath
      else
        return {
          EsyInstall.EsyOpamFile.
          override = None;
          source = Source.LocalPath {path; manifest = None;};
        }
    in
    return (Installed {opam; info; name})

  let ofFiles paths =
    let open RunAsync.Syntax in
    let%bind opams =

      let readOpam path =
        let%bind data = Fs.readFile path in
        if String.trim data = ""
        then return None
        else
          let opam = OpamFile.OPAM.read_from_string data in
          let name = Path.(path |> remExt |> basename) in
          return (Some (name, opam))
      in

      paths
      |> List.map ~f:readOpam
      |> RunAsync.List.joinAll
    in

    return (AggregatedRoot (List.filterNone opams))

  let release _ = None

  let description _ = None
  let license _ = None

  let build m =
    let buildCommands =
      match m with
      | Installed manifest ->
        begin match manifest.info.override with
        | Some {EsyInstall.Package.OpamOverride. build = Some build; _} ->
          Build.EsyCommands build
        | Some {EsyInstall.Package.OpamOverride. build = None; _}
        | None ->
          Build.OpamCommands (OpamFile.OPAM.build manifest.opam)
        end
      | AggregatedRoot [_name, opam] ->
        Build.OpamCommands (OpamFile.OPAM.build opam)
      | AggregatedRoot _ ->
        Build.OpamCommands []
    in

    let installCommands =
      match m with
      | Installed manifest ->
        begin match manifest.info.override with
        | Some {EsyInstall.Package.OpamOverride. install = Some install; _} ->
          Build.EsyCommands install
        | Some {EsyInstall.Package.OpamOverride. install = None; _}
        | None ->
          Build.OpamCommands (OpamFile.OPAM.install manifest.opam)
        end
      | AggregatedRoot [_name, opam] ->
        Build.OpamCommands (OpamFile.OPAM.install opam)
      | AggregatedRoot _ ->
        Build.OpamCommands []
    in

    let patches =
      match m with
      | Installed manifest ->
        let patches = OpamFile.OPAM.patches manifest.opam in
        let f (name, filter) =
          let name = Path.v (OpamFilename.Base.to_string name) in
          (name, filter)
        in
        List.map ~f patches
      | AggregatedRoot _ -> []
    in

    let substs =
      match m with
      | Installed manifest ->
        let names = OpamFile.OPAM.substs manifest.opam in
        let f name = Path.v (OpamFilename.Base.to_string name) in
        List.map ~f names
      | AggregatedRoot _ -> []
    in

    let buildType =
      match m with
      | Installed _ -> BuildType.InSource
      | AggregatedRoot _ -> BuildType.Unsafe
    in

    let exportedEnv =
      match m with
      | Installed manifest ->
        begin match manifest.info.override with
        | Some {EsyInstall.Package.OpamOverride. exportedEnv;_} -> exportedEnv
        | None -> ExportedEnv.empty
        end
      | AggregatedRoot _ -> ExportedEnv.empty
    in

    Some {
      Build.
      buildType;
      exportedEnv;
      buildEnv = Env.empty;
      buildCommands;
      installCommands;
      patches;
      substs;
    }

  let scripts _ = Run.return Scripts.empty

  let sandboxEnv _ = Run.return Env.empty

end

module EsyOrOpamManifest : sig
  include MANIFEST

  val dirHasManifest : Path.t -> bool RunAsync.t
  val ofSandboxSpec : SandboxSpec.t -> (t * Path.Set.t) RunAsync.t
  val ofDir :
    ?name:string
    -> ?manifest:SandboxSpec.ManifestSpec.t
    -> Path.t
    -> (t * Path.Set.t) option RunAsync.t

end = struct
  type t =
    | Esy of Esy.t
    | Opam of Opam.t

  let name (m : t) =
    match m with
    | Opam m -> Opam.name m
    | Esy m -> Esy.name m

  let version (m : t) =
    match m with
    | Opam m -> Opam.version m
    | Esy m -> Esy.version m

  let description m =
    match m with
    | Opam m -> Opam.description m
    | Esy m -> Esy.description m

  let license m =
    match m with
    | Opam m -> Opam.license m
    | Esy m -> Esy.license m

  let dependencies m =
    match m with
    | Opam m -> Opam.dependencies m
    | Esy m -> Esy.dependencies m

  let build m =
    match m with
    | Opam m -> Opam.build m
    | Esy m -> Esy.build m

  let release m =
    match m with
    | Opam m -> Opam.release m
    | Esy m -> Esy.release m

  let scripts m =
    match m with
    | Opam m -> Opam.scripts m
    | Esy m -> Esy.scripts m

  let sandboxEnv m =
    match m with
    | Opam m -> Opam.sandboxEnv m
    | Esy m -> Esy.sandboxEnv m

  let ofDir ?name ?manifest (path : Path.t) =
    let open RunAsync.Syntax in

    let discoverOfDir path =

      let filenames =
        let dirname = Path.basename path in
        [
          `Esy, Path.v "esy.json";
          `Esy, Path.v "package.json";
          `Opam, Path.(v "_esy" / "opam");
          `Opam, Path.(v dirname |> addExt ".opam");
          `Opam, Path.v "opam";
        ]
      in

      let rec tryLoad = function
        | [] -> return None
        | (kind, fname)::rest ->
          let fname = Path.(path // fname) in
          if%bind Fs.exists fname
          then (
            match kind with
            | `Esy ->
              let%bind manifest = Esy.ofFile fname in
              return (Some (Esy manifest, Path.Set.singleton fname))
            | `Opam ->
              let name =
                match name with
                | Some name -> name
                | None -> Path.basename path
              in
              let%bind manifest = Opam.ofFile ~name fname in
              return (Some (Opam manifest, Path.Set.singleton fname))
          )
          else tryLoad rest
      in

      tryLoad filenames
    in

    match manifest with
    | None -> discoverOfDir path
    | Some (SandboxSpec.ManifestSpec.OpamAggregated _) ->
      errorf "unable to load manifest from aggregated opam files"
    | Some (SandboxSpec.ManifestSpec.Esy fname) ->
      let path = Path.(path / fname) in
      let%bind manifest = Esy.ofFile path in
      return (Some (Esy manifest, Path.Set.singleton path))
    | Some (SandboxSpec.ManifestSpec.Opam fname) ->
      let path = Path.(path / fname) in
      let%bind manifest = Opam.ofFile ?name path in
      return (Some (Opam manifest, Path.Set.singleton path))

  let ofSandboxSpec (spec : SandboxSpec.t) =
    let open RunAsync.Syntax in
    match spec.manifest with
    | SandboxSpec.ManifestSpec.Esy fname ->
      let path = Path.(spec.path / fname) in
      let%bind manifest = Esy.ofFile path in
      return (Esy manifest, Path.Set.singleton path)
    | SandboxSpec.ManifestSpec.Opam fname ->
      let path = Path.(spec.path / fname) in
      let%bind manifest = Opam.ofFiles [path] in
      return (Opam manifest, Path.Set.singleton path)
    | SandboxSpec.ManifestSpec.OpamAggregated fnames ->
      let paths = List.map ~f:(fun fname -> Path.(spec.path / fname)) fnames in
      let%bind manifest = Opam.ofFiles paths in
      return (Opam manifest, Path.Set.of_list paths)

  let dirHasManifest (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind names = Fs.listDir path in
    let f = function
      | "esy.json" | "package.json" | "opam" -> true
      | name -> Path.(name |> v |> hasExt ".opam")
    in
    return (List.exists ~f names)
end

include EsyOrOpamManifest
