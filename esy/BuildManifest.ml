open EsyPackageConfig

module BuildType = struct
  include BuildType
  include BuildType.AsInPackageJson
end

module Solution = EsyInstall.Solution
module SandboxSpec = EsyInstall.SandboxSpec
module Package = EsyInstall.Package
module SourceType = SourceType
module DistResolver = EsyInstall.DistResolver
module Installation = EsyInstall.Installation

let ensurehasOpamScope name =
  match Astring.String.cut ~sep:"@opam/" name with
  | Some ("", _) -> name
  | Some _
  | None -> "@opam/" ^ name

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
  | NoCommands
  [@@deriving to_yojson]

let pp_commands fmt cmds =
  match cmds with
  | OpamCommands cmds ->
    let json = `List (List.map ~f:OpamTypes.command_to_yojson cmds) in
    Fmt.pf fmt "OpamCommands %a" (Json.pp ~std:true) json
  | EsyCommands cmds ->
    let json = CommandList.to_yojson cmds in
    Fmt.pf fmt "EsyCommands %a" (Json.pp ~std:true) json
  | NoCommands ->
    Fmt.pf fmt "NoCommands"

type patch = Path.t * OpamTypes.filter option

let patch_to_yojson (path, filter) =
  let filter =
    match filter with
    | None -> `Null
    | Some filter -> `String (OpamFilter.to_string filter)
  in
  `Assoc ["path", Path.to_yojson path; "filter", filter]

let pp_patch fmt (path, _) = Fmt.pf fmt "Patch %a" Path.pp path

type t = {
  name : string option;
  version : Version.t option;
  buildType : BuildType.t;
  build : commands;
  buildDev : CommandList.t option;
  install : commands;
  patches : patch list;
  substs : Path.t list;
  exportedEnv : ExportedEnv.t;
  buildEnv : BuildEnv.t;
} [@@deriving to_yojson, show]

let empty ~name ~version () = {
  name;
  version;
  buildType = BuildType.OutOfSource;
  build = EsyCommands [];
  buildDev = None;
  install = NoCommands;
  patches = [];
  substs = [];
  exportedEnv = ExportedEnv.empty;
  buildEnv = StringMap.empty;
}

let applyOverride (manifest : t) (override : Override.build) =

  let {
    Override.
    buildType;
    build;
    install;
    exportedEnv;
    exportedEnvOverride;
    buildEnv;
    buildEnvOverride;
  } = override in

  let manifest =
    match buildType with
    | None -> manifest
    | Some buildType -> {manifest with buildType = buildType;}
  in

  let manifest =
    match build with
    | None -> manifest
    | Some commands -> {
        manifest with
        build = EsyCommands commands;
      }
  in

  let manifest =
    match install with
    | None -> manifest
    | Some commands -> {
        manifest with
        install = EsyCommands commands;
      }
  in

  let manifest =
    match exportedEnv with
    | None -> manifest
    | Some exportedEnv -> {manifest with exportedEnv;}
  in

  let manifest =
    match exportedEnvOverride with
    | None -> manifest
    | Some override -> {
        manifest with
        exportedEnv = StringMap.Override.apply manifest.exportedEnv override;
      }
  in

  let manifest =
    match buildEnv with
    | None -> manifest
    | Some buildEnv -> {manifest with buildEnv;}
  in

  let manifest =
    match buildEnvOverride with
    | None -> manifest
    | Some override -> {
        manifest with
        buildEnv = StringMap.Override.apply manifest.buildEnv override
      }
  in

  manifest

module EsyBuild = struct
  type packageJson = {
    name: string option [@default None];
    version: Version.t option [@default None];
    esy: packageJsonEsy option [@default None];
  } [@@deriving (of_yojson {strict = false})]

  and packageJsonEsy = {
    build: (CommandList.t [@default CommandList.empty]);
    buildDev: (CommandList.t option [@default None]);
    install: (CommandList.t [@default CommandList.empty]);
    buildsInSource: (BuildType.t [@default BuildType.OutOfSource]);
    exportedEnv: (ExportedEnv.t [@default ExportedEnv.empty]);
    buildEnv: (BuildEnv.t [@default BuildEnv.empty]);
    sandboxEnv: (SandboxEnv.t [@default SandboxEnv.empty]);
  } [@@deriving (of_yojson { strict = false })]

  let ofData data =
    let open Run.Syntax in
    let%bind json = Json.parse data in
    let%bind pkgJson = Json.parseJsonWith packageJson_of_yojson json in
    match pkgJson.esy with
    | Some m ->
      let build = {
        name = pkgJson.name;
        version = pkgJson.version;
        buildType = m.buildsInSource;
        exportedEnv = m.exportedEnv;
        buildEnv = m.buildEnv;
        build = EsyCommands (m.build);
        buildDev = m.buildDev;
        install = EsyCommands (m.install);
        patches = [];
        substs = [];
      } in
      return (Some build)
    | None -> return None

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind data = Fs.readFile path in
    match ofData data with
    | Ok (Some manifest) -> return (Some manifest, Path.Set.singleton path)
    | Ok None -> return (None, Path.Set.empty)
    | Error err -> Lwt.return (Error err)
end

let parseOpam data =
  let open Run.Syntax in
  if String.trim data = ""
  then return None
  else (
    let%bind opam =
      try return (OpamFile.OPAM.read_from_string data)
      with
      | Failure msg -> errorf "error parsing opam: %s" msg
      | _ -> errorf " error parsing opam"
    in
    return (Some opam)
  )

module OpamBuild = struct

  let buildOfOpam ~name ~version (opam : OpamFile.OPAM.t) =
    let build = OpamCommands (OpamFile.OPAM.build opam) in
    let install = OpamCommands (OpamFile.OPAM.install opam) in

    let patches =
      let patches = OpamFile.OPAM.patches opam in
      let f (name, filter) =
        let name = Path.v (OpamFilename.Base.to_string name) in
        (name, filter)
      in
      List.map ~f patches
    in

    let substs =
      let names = OpamFile.OPAM.substs opam in
      let f name = Path.v (OpamFilename.Base.to_string name) in
      List.map ~f names
    in

    let name =
      match name with
      | Some name -> Some (ensurehasOpamScope name)
      | None -> None
    in

    {
      name;
      version;
      buildType = BuildType.InSource;
      exportedEnv = ExportedEnv.empty;
      buildEnv = BuildEnv.empty;
      build;
      buildDev = None;
      install;
      patches;
      substs;
    }

  let ofData ~nameFallback data =
    let open Run.Syntax in
    match%bind parseOpam data with
    | None -> return None
    | Some opam ->
      let name =
        try Some (OpamPackage.Name.to_string (OpamFile.OPAM.name opam))
        with _ -> nameFallback
      in
      let version =
        try Some (Version.Opam (OpamFile.OPAM.version opam))
        with _ -> None
      in
      return (Some (buildOfOpam ~name ~version opam))

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind data = Fs.readFile path in
    match ofData ~nameFallback:None data with
    | Ok None -> errorf "unable to load opam manifest at %a" Path.pp path
    | Ok Some manifest -> return (Some manifest, Path.Set.singleton path)
    | Error err -> Lwt.return (Error err)

end

let discoverManifest path =
  let open RunAsync.Syntax in

  let filenames = [
    ManifestSpec.Esy, "esy.json";
    ManifestSpec.Esy, "package.json";
  ] in

  let rec tryLoad = function
    | [] -> return (None, Path.Set.empty)
    | (kind, fname)::rest ->
      Logs_lwt.debug (fun m ->
        m "trying %a %a"
        Path.pp path
        ManifestSpec.pp (kind, fname)
      );%lwt
      let fname = Path.(path / fname) in
      if%bind Fs.exists fname
      then
        match kind with
        | ManifestSpec.Esy -> EsyBuild.ofFile fname
        | ManifestSpec.Opam -> OpamBuild.ofFile fname
      else tryLoad rest
  in

  tryLoad filenames

let ofPath ?manifest (path : Path.t) =
  Logs_lwt.debug (fun m ->
    m "BuildManifest.ofPath %a %a"
    Fmt.(option ManifestSpec.pp) manifest
    Path.pp path
  );%lwt

  let manifest =
    match manifest with
    | None -> discoverManifest path
    | Some spec ->
      begin match spec with
      | ManifestSpec.Esy, fname ->
        let path = Path.(path / fname) in
        EsyBuild.ofFile path
      | ManifestSpec.Opam, fname ->
        let path = Path.(path / fname) in
        OpamBuild.ofFile path
      end
    in

    RunAsync.contextf manifest
      "reading package metadata from %a"
      Path.ppPretty path

let ofInstallationLocation ~cfg (pkg : Package.t) (loc : Installation.location) =
  let open RunAsync.Syntax in
  match pkg.source with
  | Link { path; manifest; } ->
    let dist = Dist.LocalPath {path; manifest;} in
    let%bind res =
      DistResolver.resolve
        ~cfg:cfg.Config.installCfg
        ~sandbox:cfg.spec
        dist
    in
    let overrides = Overrides.merge pkg.overrides res.DistResolver.overrides in
    let%bind manifest =
      begin match res.DistResolver.manifest with
      | Some {kind = ManifestSpec.Esy; filename = _; data; suggestedPackageName = _;} ->
        RunAsync.ofRun (EsyBuild.ofData data)
      | Some {kind = ManifestSpec.Opam; filename = _; data; suggestedPackageName;} ->
        RunAsync.ofRun (OpamBuild.ofData ~nameFallback:(Some suggestedPackageName) data)
      | None ->
        let manifest = empty ~name:None ~version:None () in
        return (Some manifest)
      end
    in
    begin match manifest with
    | None ->
      if Overrides.isEmpty overrides
      then return (None, res.DistResolver.paths)
      else
        let manifest = empty ~name:None ~version:None () in
        let%bind manifest =
          Overrides.foldWithBuildOverrides
            ~f:applyOverride
            ~init:manifest
            overrides
        in
        return (Some manifest, res.DistResolver.paths)
    | Some manifest ->
      let%bind manifest =
        Overrides.foldWithBuildOverrides
          ~f:applyOverride
          ~init:manifest
          overrides
      in
      return (Some manifest, res.DistResolver.paths)
    end

  | Install { source = source, _; opam = _ } ->
    begin match%bind Package.opam pkg with
    | Some (name, version, opamfile) ->
      let manifest =
        OpamBuild.buildOfOpam
          ~name:(Some name)
          ~version:(Some version)
          opamfile
      in
      let%bind manifest =
        Overrides.foldWithBuildOverrides
          ~f:applyOverride
          ~init:manifest
          pkg.overrides
      in
      return (Some manifest, Path.Set.empty)
    | None ->
      let manifest = Dist.manifest source in
      let%bind manifest, paths = ofPath ?manifest loc in
      let%bind manifest =
        match manifest with
        | Some manifest ->
          let%bind manifest =
            Overrides.foldWithBuildOverrides
              ~f:applyOverride
              ~init:manifest
              pkg.overrides
          in
          return (Some manifest)
        | None ->
          if Overrides.isEmpty pkg.overrides
          then return None
          else
            let manifest = empty ~name:None ~version:None () in
            let%bind manifest =
              Overrides.foldWithBuildOverrides
                ~f:applyOverride
                ~init:manifest
                pkg.overrides
            in
            return (Some manifest)
      in
      return (manifest, paths)
    end
