open EsyPackageConfig

let ofPackageJson (path : Path.t) =
  let open RunAsync.Syntax in
  let%bind json = Fs.readJsonFile path in
  match OfPackageJson.buildManifest json with
  | Ok (Some manifest) -> return (Some manifest, Path.Set.singleton path)
  | Ok None -> return (None, Path.Set.empty)
  | Error err -> Lwt.return (Error err)

let applyOverride (manifest : BuildManifest.t) (override : Override.build) =

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

let ensurehasOpamScope name =
  match Astring.String.cut ~sep:"@opam/" name with
  | Some ("", _) -> name
  | Some _
  | None -> "@opam/" ^ name

module OpamBuild = struct

  let buildOfOpam ~name ~version (opam : OpamFile.OPAM.t) =
    let build = BuildManifest.OpamCommands (OpamFile.OPAM.build opam) in
    let install = BuildManifest.OpamCommands (OpamFile.OPAM.install opam) in

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
      BuildManifest.
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
      let warnings = [] in
      return (Some (buildOfOpam ~name ~version opam, warnings))

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind data = Fs.readFile path in
    match ofData ~nameFallback:None data with
    | Ok None -> errorf "unable to load opam manifest at %a" Path.pp path
    | Ok Some manifest ->
      return (Some manifest, Path.Set.singleton path)
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
      let%lwt () = Logs_lwt.debug (fun m ->
        m "trying %a %a"
        Path.pp path
        ManifestSpec.pp (kind, fname)
      ) in
      let fname = Path.(path / fname) in
      if%bind Fs.exists fname
      then
        match kind with
        | ManifestSpec.Esy -> ofPackageJson fname
        | ManifestSpec.Opam -> OpamBuild.ofFile fname
      else tryLoad rest
  in

  tryLoad filenames

let ofPath ?manifest (path : Path.t) =
  let%lwt () = Logs_lwt.debug (fun m ->
    m "BuildManifest.ofPath %a %a"
    Fmt.(option ManifestSpec.pp) manifest
    Path.pp path
  ) in

  let manifest =
    match manifest with
    | None -> discoverManifest path
    | Some spec ->
      begin match spec with
      | ManifestSpec.Esy, fname ->
        let path = Path.(path / fname) in
        ofPackageJson path
      | ManifestSpec.Opam, fname ->
        let path = Path.(path / fname) in
        OpamBuild.ofFile path
      end
    in

    RunAsync.contextf manifest
      "reading package metadata from %a"
      Path.ppPretty path

let ofInstallationLocation cfg installCfg (pkg : EsyInstall.Package.t) (loc : EsyInstall.Installation.location) =
  let open RunAsync.Syntax in
  match pkg.source with
  | Link { path; manifest; kind = _; } ->
    let dist = Dist.LocalPath {path; manifest;} in
    let%bind res =
      EsyInstall.DistResolver.resolve
        ~cfg:installCfg
        ~sandbox:cfg.Config.spec
        dist
    in
    let overrides = Overrides.merge pkg.overrides res.EsyInstall.DistResolver.overrides in
    let%bind manifest =
      begin match res.EsyInstall.DistResolver.manifest with
      | Some {kind = ManifestSpec.Esy; filename = _; data; suggestedPackageName = _;} ->
        RunAsync.ofRun (
          let open Run.Syntax in
          let%bind json = Json.parse data in
          OfPackageJson.buildManifest json
        )
      | Some {kind = ManifestSpec.Opam; filename = _; data; suggestedPackageName;} ->
        RunAsync.ofRun (OpamBuild.ofData ~nameFallback:(Some suggestedPackageName) data)
      | None ->
        let manifest = BuildManifest.empty ~name:None ~version:None () in
        return (Some (manifest, []))
      end
    in
    begin match manifest with
    | None ->
      if Overrides.isEmpty overrides
      then return (None, res.EsyInstall.DistResolver.paths)
      else
        let manifest = BuildManifest.empty ~name:None ~version:None () in
        let%bind manifest =
          Overrides.foldWithBuildOverrides
            ~f:applyOverride
            ~init:manifest
            overrides
        in
        return (Some manifest, res.EsyInstall.DistResolver.paths)
    | Some (manifest, _warnings) ->
      let%bind manifest =
        Overrides.foldWithBuildOverrides
          ~f:applyOverride
          ~init:manifest
          overrides
      in
      return (Some manifest, res.EsyInstall.DistResolver.paths)
    end

  | Install { source = source, _; opam = _ } ->
    begin match%bind EsyInstall.Package.opam pkg with
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
        | Some (manifest, _warnings) ->
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
            let manifest = BuildManifest.empty ~name:None ~version:None () in
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
