module BuildType = struct
  include EsyLib.BuildType
  include EsyLib.BuildType.AsInPackageJson
end

module SandboxSpec = EsyInstall.SandboxSpec
module ManifestSpec = EsyInstall.ManifestSpec
module Package = EsyInstall.Package
module Source = EsyInstall.Source
module SourceType = EsyLib.SourceType
module Command = Package.Command
module CommandList = Package.CommandList
module ExportedEnv = Package.ExportedEnv
module Env = Package.Env
module SourceResolver = EsyInstall.SourceResolver
module Overrides = EsyInstall.Package.Overrides

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
    exportedEnv = ExportedEnv.empty;
    buildEnv = StringMap.empty;
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
  [@@deriving ord]

  type t =
    script StringMap.t
    [@@deriving ord]

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
    Json.Decode.stringMap script

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

module type QUERY_MANIFEST = sig
  include MANIFEST

  [@@@ocaml.warning "-32"]
  val manifest : t
end

module EsyManifest : sig
  include MANIFEST

  val ofFile : Path.t -> t RunAsync.t
  val ofString : filename:string -> string -> t Run.t
end = struct

  module EsyManifest = struct

    type t = {
      build: (CommandList.t [@default CommandList.empty]);
      install: (CommandList.t [@default CommandList.empty]);
      buildsInSource: (BuildType.t [@default BuildType.OutOfSource]);
      exportedEnv: (ExportedEnv.t [@default ExportedEnv.empty]);
      buildEnv: (Env.t [@default Env.empty]);
      sandboxEnv: (Env.t [@default Env.empty]);
      release: (Release.t option [@default None]);
    } [@@deriving (of_yojson { strict = false })]

  end

  module JsonManifest = struct
    type t = {
      name : string option [@default None];
      version : string option [@default None];
      description : string option [@default None];
      license : Json.t option [@default None];
      dependencies : Package.NpmFormula.t [@default Package.NpmFormula.empty];
      peerDependencies : Package.NpmFormula.t [@default Package.NpmFormula.empty];
      devDependencies : Package.NpmFormula.t [@default Package.NpmFormula.empty];
      optDependencies : Package.NpmFormula.t [@default Package.NpmFormula.empty];
      buildTimeDependencies : Package.NpmFormula.t [@default Package.NpmFormula.empty];
      esy: EsyManifest.t option [@default None];
    } [@@deriving (of_yojson {strict = false})]
  end

  type manifest = {
    name : string;
    version : string;
    description : string option;
    license : Json.t option;
    dependencies : Package.NpmFormula.t;
    peerDependencies : Package.NpmFormula.t;
    devDependencies : Package.NpmFormula.t;
    optDependencies : Package.NpmFormula.t;
    buildTimeDependencies : Package.NpmFormula.t;
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

  let ofJsonManifest ~defaultName (jsonManifest: JsonManifest.t) =
    let name =
      match jsonManifest.name with
      | Some name  -> name
      | None -> defaultName
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

  let ofString ~filename (data : string) =
    let open Run.Syntax in
    let%bind json = Json.parse data in
    let%bind jsonManifest = Json.parseJsonWith JsonManifest.of_yojson json in
    let manifest =
      let defaultName = Path.(v filename |> remExt |> show) in
      ofJsonManifest ~defaultName jsonManifest
    in
    return (manifest, json)

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind json = Fs.readJsonFile path in
    let%bind jsonManifest =
      RunAsync.ofRun (Json.parseJsonWith JsonManifest.of_yojson json)
    in
    let manifest =
      let defaultName = Path.basename path in
      ofJsonManifest ~defaultName jsonManifest
    in
    return (manifest, json)

end

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

let parseOpam data =
  if String.trim data = ""
  then None
  else Some (OpamFile.OPAM.read_from_string data)

let readOpam path =
  let open RunAsync.Syntax in
  let%bind data = Fs.readFile path in
  let name = Path.(path |> remExt |> basename) in
  match parseOpam data with
  | Some opam -> return (Some (name, opam))
  | None -> return None

module OpamManifest : sig
  include MANIFEST

  val ofInstallationDir : Path.t -> t option RunAsync.t
  val ofFile : Path.t -> t RunAsync.t
  val ofString : filename:string -> string -> t Run.t
end = struct
  type t = EsyInstall.Solution.Record.Opam.t

  let opamname (manifest : t) =
    let name =
      try OpamFile.OPAM.name manifest.opam
      with _ -> manifest.name
    in
    OpamPackage.Name.to_string name

  let name (manifest : t) = "@opam/" ^ (opamname manifest)

  let version (manifest : t) =
    let version =
      try OpamFile.OPAM.version manifest.opam
      with _ -> manifest.version
    in
    OpamPackage.Version.to_string version

  let dependencies (manifest : t) =
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

      let dependencies = dependsOfOpam manifest.opam in
      match manifest.override with
      | Some {EsyInstall.Package.OpamOverride. dependencies = extraDependencies; _} ->
        let extraDependencies =
          extraDependencies
          |> List.map ~f:(fun req -> [req.EsyInstall.Req.name])
        in
        List.append dependencies extraDependencies
      | None -> dependencies
    in

    let optDependencies =
      let dependencies =
        let f = OpamFile.OPAM.depopts manifest.opam in
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
    in
    {
      Dependencies.
      dependencies;
      buildTimeDependencies = [];
      devDependencies = [];
      optDependencies;
    }

  let release _ = None
  let description _ = None
  let license _ = None

  let build (manifest : t) =
    let buildCommands =
      match manifest.override with
      | Some {EsyInstall.Package.OpamOverride. build = Some build; _} ->
        Build.EsyCommands build
      | Some {EsyInstall.Package.OpamOverride. build = None; _}
      | None ->
        Build.OpamCommands (OpamFile.OPAM.build manifest.opam)
    in

    let installCommands =
      match manifest.override with
      | Some {EsyInstall.Package.OpamOverride. install = Some install; _} ->
        Build.EsyCommands install
      | Some {EsyInstall.Package.OpamOverride. install = None; _}
      | None ->
        Build.OpamCommands (OpamFile.OPAM.install manifest.opam)
    in

    let patches =
      let patches = OpamFile.OPAM.patches manifest.opam in
      let f (name, filter) =
        let name = Path.v (OpamFilename.Base.to_string name) in
        (name, filter)
      in
      List.map ~f patches
    in

    let substs =
      let names = OpamFile.OPAM.substs manifest.opam in
      let f name = Path.v (OpamFilename.Base.to_string name) in
      List.map ~f names
    in

    let exportedEnv =
      match manifest.override with
      | Some {EsyInstall.Package.OpamOverride. exportedEnv;_} -> exportedEnv
      | None -> ExportedEnv.empty
    in

    Some {
      Build.
      (* we assume opam installations are built in source *)
      buildType = BuildType.InSource;
      exportedEnv;
      buildEnv = Env.empty;
      buildCommands;
      installCommands;
      patches;
      substs;
    }

  let scripts _ = Run.return Scripts.empty

  let sandboxEnv _ = Run.return Env.empty

  let ofInstallationDir (path : Path.t) =
    let open RunAsync.Syntax in
    match%bind EsyInstall.EsyLinkFile.ofDirIfExists path with
    | None
    | Some { EsyInstall.EsyLinkFile. opam = None; _ } ->
      return None
    | Some { EsyInstall.EsyLinkFile. opam = Some info; _ } ->
      return (Some info)

  let ofString ~filename (data : string) =
    let open Run.Syntax in
    let name = Path.(v filename |> remExt |> show) in
    match parseOpam data with
    | None -> error "empty opam file"
    | Some opam ->
      let version = "dev" in
      return {
        EsyInstall.Solution.Record.Opam.
        name = OpamPackage.Name.of_string name;
        version = OpamPackage.Version.of_string version;
        opam;
        override = None;
      }

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    match%bind readOpam path with
    | None -> errorf "unable to load opam manifest at %a" Path.pp path
    | Some (_, opam) ->
      let name = Path.(basename (parent path)) in
      let version = "dev" in
      return {
        EsyInstall.Solution.Record.Opam.
        name = OpamPackage.Name.of_string name;
        version = OpamPackage.Version.of_string version;
        opam;
        override = None;
      }
end

module OpamRootManifest : sig
  include MANIFEST

  val ofFiles :
    ?name:string
    -> Path.t list
    -> t RunAsync.t

end = struct
  type t = {
    name : string option;
    opam : (string * OpamFile.OPAM.t) list;
  }

  let opamname _ = "root"

  let name manifest =
    match manifest with
    | {name = Some name; _} -> name
    | manifest -> "@opam/" ^ (opamname manifest)

  let version _ = "dev"

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
      let namesPresent =
        let f names (name, _) = StringSet.add ("@opam/" ^ name) names in
        List.fold_left ~f ~init:StringSet.empty manifest.opam
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
      List.fold_left ~f ~init:[] manifest.opam
    in

    {
      Dependencies.
      dependencies;
      buildTimeDependencies = [];
      devDependencies = [];
      optDependencies = [];
    }

  let release _ = None

  let description _ = None
  let license _ = None

  let build m =
    let buildCommands =
      match m with
      | {opam = [_name, opam]; _} ->
        Build.OpamCommands (OpamFile.OPAM.build opam)
      | _ ->
        Build.OpamCommands []
    in

    let installCommands =
      match m with
      | {opam = [_name, opam]; _} ->
        Build.OpamCommands (OpamFile.OPAM.install opam)
      | _ ->
        Build.OpamCommands []
    in

    Some {
      Build.
      buildType = BuildType.Unsafe;
      exportedEnv = ExportedEnv.empty;
      buildEnv = Env.empty;
      buildCommands;
      installCommands;
      patches = [];
      substs = [];
    }

  let scripts _ = Run.return Scripts.empty

  let sandboxEnv _ = Run.return Env.empty

  let ofFiles ?name paths =
    let open RunAsync.Syntax in
    let%bind opams =
      paths
      |> List.map ~f:readOpam
      |> RunAsync.List.joinAll
    in
    return {name; opam = List.filterNone opams;}

end

module Manifest : sig
  include MANIFEST

  val dirHasManifest : Path.t -> bool RunAsync.t
  val ofSandboxSpec :
    cfg:Config.t
    -> SandboxSpec.t
    -> (t * EsyInstall.Package.Overrides.t * Path.Set.t) RunAsync.t
  val ofDir :
    ?manifest:ManifestSpec.Filename.t
    -> Path.t
    -> (t * Path.Set.t) option RunAsync.t

end = struct

  module type QUERY_MANIFEST = sig
    include MANIFEST

    val manifest : t
  end

  type t = (module QUERY_MANIFEST)

  let name (module M : QUERY_MANIFEST) = M.name M.manifest
  let version (module M : QUERY_MANIFEST) = M.version M.manifest
  let description (module M : QUERY_MANIFEST) = M.description M.manifest
  let license (module M : QUERY_MANIFEST) = M.license M.manifest
  let dependencies (module M : QUERY_MANIFEST) = M.dependencies M.manifest
  let build (module M : QUERY_MANIFEST) = M.build M.manifest
  let release (module M : QUERY_MANIFEST) = M.release M.manifest
  let scripts (module M : QUERY_MANIFEST) = M.scripts M.manifest
  let sandboxEnv (module M : QUERY_MANIFEST) = M.sandboxEnv M.manifest

  let loadEsyManifest path =
    let open RunAsync.Syntax in
    let%bind manifest = EsyManifest.ofFile path in
    let m = (module struct include EsyManifest let manifest = manifest end : QUERY_MANIFEST) in
    return (m, Path.Set.singleton path)

  let loadOpamManifest path =
    let open RunAsync.Syntax in
    let%bind manifest = OpamManifest.ofFile path in
    let m = (module struct include OpamManifest let manifest = manifest end : QUERY_MANIFEST) in
    return (m, Path.Set.singleton path)

  let loadOpamManifestOfFiles paths =
    let open RunAsync.Syntax in
    let%bind manifest = OpamRootManifest.ofFiles paths in
    let m =
      (module struct
        include OpamRootManifest
        let manifest = manifest
      end : QUERY_MANIFEST)
    in
    return (m, Overrides.empty, Path.Set.of_list paths)

  let loadOpamManifestOfInstallation path =
    let open RunAsync.Syntax in
    match%bind OpamManifest.ofInstallationDir path with
    | Some manifest ->
      let m =
        (module struct
          include OpamManifest
          let manifest = manifest
        end : QUERY_MANIFEST)
      in
      return (Some (m, Path.Set.empty))
    | None -> return None

  let discoverManifest path =
    let open RunAsync.Syntax in

    let filenames =
      let dirname = Path.basename path in
      [
        `Esy, Path.v "esy.json";
        `Esy, Path.v "package.json";
        `Opam, Path.(v dirname |> addExt ".opam");
        `Opam, Path.v "opam";
      ]
    in

    let rec tryLoad = function
      | [] -> return None
      | (kind, fname)::rest ->
        let fname = Path.(path // fname) in
        if%bind Fs.exists fname
        then
          let%bind manifest =
            match kind with
            | `Esy -> loadEsyManifest fname
            | `Opam -> loadOpamManifest fname
          in
          return (Some manifest)
        else tryLoad rest
    in

    tryLoad filenames

  let ofDir ?manifest (path : Path.t) =
    let open RunAsync.Syntax in

    let manifest =
      match manifest with
      | None ->
        begin match%bind loadOpamManifestOfInstallation path with
        | Some manifest -> return (Some manifest)
        | None -> discoverManifest path
        end
      | Some spec ->
        let%bind manifest =
          match spec with
          | ManifestSpec.Filename.Esy, fname ->
            let path = Path.(path / fname) in
            loadEsyManifest path
          | ManifestSpec.Filename.Opam, fname ->
            let path = Path.(path / fname) in
            loadOpamManifest path
        in
        return (Some manifest)
      in

      RunAsync.contextf manifest
        "reading package metadata from %a"
        Path.ppPretty path

  let ofSandboxSpec ~cfg (spec : SandboxSpec.t) =

    let readManifest ~path overrides {SourceResolver. kind; filename; data} =
      let open Run.Syntax in
      match kind with
      | ManifestSpec.Filename.Esy ->
        let%bind manifest = EsyManifest.ofString ~filename data in
        let m = (module struct include EsyManifest let manifest = manifest end : QUERY_MANIFEST) in
        return (m, overrides, Path.Set.singleton path)
      | ManifestSpec.Filename.Opam ->
        let%bind manifest = OpamManifest.ofString ~filename data in
        let m = (module struct include OpamManifest let manifest = manifest end : QUERY_MANIFEST) in
        return (m, overrides, Path.Set.singleton path)
    in

    match spec.manifest with
    | ManifestSpec.One (_, fname) ->
      let open RunAsync.Syntax in
      let path = Path.(spec.path / fname) in
      let%bind source = RunAsync.ofStringError (
        let source = "path:" ^ (Path.show path) in
        EsyInstall.Source.parse source
      ) in
      let%bind { SourceResolver. overrides; source = resolvedSource; manifest; } =
        SourceResolver.resolve
          ~cfg:cfg.Config.installCfg
          ~root:spec.path
          source
      in
      begin match manifest with
      | None -> errorf "no manifest found at %a" Source.pp resolvedSource
      | Some manifest ->
        let manifest = RunAsync.ofRun (readManifest ~path overrides manifest) in
        RunAsync.contextf
          manifest
          "reading package metadata from %a" Path.ppPretty path
      end
    | ManifestSpec.ManyOpam fnames ->
      let paths = List.map ~f:(fun fname -> Path.(spec.path / fname)) fnames in
      loadOpamManifestOfFiles paths

  let dirHasManifest (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind names = Fs.listDir path in
    let f = function
      | "esy.json" | "package.json" | "opam" -> true
      | name -> Path.(name |> v |> hasExt ".opam")
    in
    return (List.exists ~f names)
end

include Manifest
