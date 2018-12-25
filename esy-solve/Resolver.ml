open EsyPackageConfig

module PackageCache = Memoize.Make(struct
  type key = (string * Resolution.resolution)
  type value = (InstallManifest.t, string) result RunAsync.t
end)

module SourceCache = Memoize.Make(struct
  type key = SourceSpec.t
  type value = Source.t RunAsync.t
end)

module ResolutionCache = Memoize.Make(struct
  type key = string
  type value = Resolution.t list RunAsync.t
end)

let requireOpamName name =
  let open Run.Syntax in
  match Astring.String.cut ~sep:"@opam/" name with
  | Some ("", name) -> return (OpamPackage.Name.of_string name)
  | _ -> errorf "invalid opam package name: %s" name

let ensureOpamName name =
  let open Run.Syntax in
  match Astring.String.cut ~sep:"@opam/" name with
  | Some ("", name) -> return (OpamPackage.Name.of_string name)
  | Some _
  | None -> return (OpamPackage.Name.of_string name)

let toOpamOcamlVersion version =
  match version with
  | Some (Version.Npm { major; minor; patch; _ }) ->
    let minor =
      if minor < 10
      then "0" ^ (string_of_int minor)
      else string_of_int minor
    in
    let patch =
      if patch < 1000
      then patch
      else patch / 1000
    in
    let v = Printf.sprintf "%i.%s.%i" major minor patch in
    let v =
      match OpamPackageVersion.Version.parse v with
      | Ok v -> v
      | Error msg -> failwith msg
    in
    Some v
  | Some (Version.Opam v) -> Some v
  | Some (Version.Source _) -> None
  | None -> None

type t = {
  cfg: Config.t;
  sandbox: EsyInstall.SandboxSpec.t;
  pkgCache: PackageCache.t;
  srcCache: SourceCache.t;
  opamRegistry : OpamRegistry.t;
  npmRegistry : NpmRegistry.t;
  mutable ocamlVersion : Version.t option;
  mutable resolutions : Resolutions.t;
  resolutionCache : ResolutionCache.t;
  resolutionUsage : (Resolution.t, bool) Hashtbl.t;

  npmDistTags : (string, SemverVersion.Version.t StringMap.t) Hashtbl.t;
  sourceSpecToSource : (SourceSpec.t, Source.t) Hashtbl.t;
  sourceToSource : (Source.t, Source.t) Hashtbl.t;
}

let emptyLink ~name ~path ~manifest () =
  {
    InstallManifest.
    name;
    version = Version.Source (Source.Link {path; manifest;});
    originalVersion = None;
    originalName = None;
    source = PackageSource.Link {
      path;
      manifest = None;
    };
    overrides = Overrides.empty;
    dependencies = InstallManifest.Dependencies.NpmFormula [];
    devDependencies = InstallManifest.Dependencies.NpmFormula [];
    peerDependencies = NpmFormula.empty;
    optDependencies = StringSet.empty;
    resolutions = Resolutions.empty;
    kind = Esy;
  }

let emptyInstall ~name ~source () =
  {
    InstallManifest.
    name;
    version = Version.Source (Dist source);
    originalVersion = None;
    originalName = None;
    source = PackageSource.Install {
      source = source, [];
      opam = None;
    };
    overrides = Overrides.empty;
    dependencies = InstallManifest.Dependencies.NpmFormula [];
    devDependencies = InstallManifest.Dependencies.NpmFormula [];
    peerDependencies = NpmFormula.empty;
    optDependencies = StringSet.empty;
    resolutions = Resolutions.empty;
    kind = Esy;
  }

let make ~cfg ~sandbox () =
  RunAsync.return {
    cfg;
    sandbox;
    pkgCache = PackageCache.make ();
    srcCache = SourceCache.make ();
    opamRegistry = OpamRegistry.make ~cfg ();
    npmRegistry = NpmRegistry.make ~url:cfg.Config.npmRegistry ();
    ocamlVersion = None;
    resolutions = Resolutions.empty;
    resolutionCache = ResolutionCache.make ();
    resolutionUsage = Hashtbl.create 10;
    npmDistTags = Hashtbl.create 500;
    sourceSpecToSource = Hashtbl.create 500;
    sourceToSource = Hashtbl.create 500;
  }

let setOCamlVersion ocamlVersion resolver =
  resolver.ocamlVersion <- Some ocamlVersion

let setResolutions resolutions resolver =
  resolver.resolutions <- resolutions

let getUnusedResolutions resolver =
  let nameIfUnused usage (resolution:Resolution.t) =
    match Hashtbl.find_opt usage resolution with
    | Some true -> None
    | _         -> Some resolution.name
  in
  List.filter_map ~f:(nameIfUnused resolver.resolutionUsage) (Resolutions.entries resolver.resolutions)

(* This function increments the resolution usage count of that resolution *)
let markResolutionAsUsed resolver resolution =
  Hashtbl.replace resolver.resolutionUsage resolution true

let sourceMatchesSpec resolver spec source =
  match Hashtbl.find_opt resolver.sourceSpecToSource spec with
  | Some resolvedSource ->
    if Source.compare resolvedSource source = 0
    then true
    else
      begin match Hashtbl.find_opt resolver.sourceToSource resolvedSource with
      | Some resolvedSource -> Source.compare resolvedSource source = 0
      | None -> false
      end
  | None -> false

let versionMatchesReq (resolver : t) (req : Req.t) name (version : Version.t) =
  let checkVersion () =
    match req.spec, version with

    | (VersionSpec.Npm spec, Version.Npm version) ->
      SemverVersion.Formula.DNF.matches ~version spec

    | (VersionSpec.NpmDistTag tag, Version.Npm version) ->
      begin match Hashtbl.find_opt resolver.npmDistTags req.name with
      | Some tags ->
        begin match StringMap.find_opt tag tags with
        | None -> false
        | Some taggedVersion ->
          SemverVersion.Version.compare version taggedVersion = 0
        end
      | None -> false
      end

    | (VersionSpec.Opam spec, Version.Opam version) ->
      OpamPackageVersion.Formula.DNF.matches ~version spec

    | (VersionSpec.Source spec, Version.Source source) ->
      sourceMatchesSpec resolver spec source

    | (VersionSpec.Npm _, _) -> false
    | (VersionSpec.NpmDistTag _, _) -> false
    | (VersionSpec.Opam _, _) -> false
    | (VersionSpec.Source _, _) -> false
  in
  let checkResolutions () =
    match Resolutions.find resolver.resolutions req.name with
    | Some _ -> true
    | None -> false
  in
  req.name = name && (checkResolutions () || checkVersion ())

let versionMatchesDep (resolver : t) (dep : InstallManifest.Dep.t) name (version : Version.t) =
  let checkVersion () =
    match version, dep.InstallManifest.Dep.req with

    | Version.Npm version, Npm spec ->
      SemverVersion.Constraint.matches ~version spec

    | Version.Opam version, Opam spec ->
      OpamPackageVersion.Constraint.matches ~version spec

    | Version.Source source, Source spec ->
      sourceMatchesSpec resolver spec source

    | Version.Npm _, _ -> false
    | Version.Opam _, _ -> false
    | Version.Source _, _ -> false
  in
  let checkResolutions () =
    match Resolutions.find resolver.resolutions dep.name with
    | Some _ -> true
    | None -> false
  in
  dep.name = name && (checkResolutions () || checkVersion ())

let packageOfSource ~name ~overrides (source : Source.t) resolver =
  let open RunAsync.Syntax in

  let readManifest ~name ~source {EsyInstall.DistResolver. kind; filename = _; data; suggestedPackageName} =
    let open RunAsync.Syntax in
    match kind with
    | ManifestSpec.Esy ->
      let%bind manifest = RunAsync.ofRun (
        let open Run.Syntax in
        let%bind json = Json.parse data in
        OfPackageJson.installManifest
          ~parseResolutions:true
          ~parseDevDependencies:true
          ~name
          ~version:(Version.Source source)
          ~source
          json
      ) in
      return (Ok manifest)
    | ManifestSpec.Opam ->
      let%bind opamname = RunAsync.ofRun (
        ensureOpamName suggestedPackageName
      ) in
      let%bind manifest = RunAsync.ofRun (
        let version = OpamPackage.Version.of_string "dev" in
        OpamManifest.ofString ~name:opamname ~version data
      ) in
      OpamManifest.toInstallManifest ~name ~version:(Version.Source source) ~source manifest
  in

  let pkg =
    let%bind { EsyInstall.DistResolver. overrides; dist = resolvedDist; manifest; _; } =
      EsyInstall.DistResolver.resolve
        ~cfg:resolver.cfg.installCfg
        ~sandbox:resolver.sandbox
        ~overrides
        (Source.toDist source)
    in

    let%bind resolvedSource =
      match source, resolvedDist with
      | Source.Dist _, _ -> return (Source.Dist resolvedDist)
      | Source.Link _, Dist.LocalPath {path; manifest;} ->
        return (Source.Link {path; manifest;})
      | Source.Link _, dist -> errorf "unable to link to %a" Dist.pp dist
    in

    let%bind pkg =
      match manifest with
      | Some manifest ->
        readManifest ~name ~source:resolvedSource manifest
      | None ->
        if not (Overrides.isEmpty overrides)
        then
          match source with
          | Source.Link {path; manifest;} ->
            let pkg = emptyLink ~name ~path ~manifest () in
            return (Ok pkg)
          | _ ->
            let pkg = emptyInstall ~name ~source:resolvedDist () in
            return (Ok pkg)
        else errorf "no manifest found at %a" Source.pp source
    in

    let pkg =
      match pkg with
      | Ok pkg -> Ok {pkg with InstallManifest.overrides}
      | err -> err
    in

    Hashtbl.replace resolver.sourceToSource source resolvedSource;

    return pkg
  in

  RunAsync.contextf pkg
    "reading package metadata from %a" Source.ppPretty source

let applyOverride pkg (override : Override.install) =
  let {
    Override.
    dependencies;
    devDependencies;
    resolutions;
  } = override in

  let applyNpmFormulaOverride dependencies override =
    match dependencies with
    | InstallManifest.Dependencies.NpmFormula formula ->
      let formula =
        let dependencies =
          let f map req = StringMap.add req.Req.name req map in
          List.fold_left ~f ~init:StringMap.empty formula
        in
        let dependencies =
          StringMap.Override.apply dependencies override
        in
        StringMap.values dependencies
      in
      InstallManifest.Dependencies.NpmFormula formula
    | InstallManifest.Dependencies.OpamFormula formula ->
      (* remove all terms which we override *)
      let formula =
        let filter dep =
          match StringMap.find_opt dep.InstallManifest.Dep.name override with
          | None -> true
          | Some _ -> false
        in
        formula
        |> List.map ~f:(List.filter ~f:filter)
        |> List.filter ~f:(function [] -> false | _ -> true)
      in
      (* now add all edits *)
      let formula =
        let edits =
          let f _name override edits =
            match override with
            | StringMap.Override.Drop -> edits
            | StringMap.Override.Edit req ->
              begin match req.Req.spec with
              | VersionSpec.Npm formula ->
                let f (c : SemverVersion.Constraint.t) =
                  {InstallManifest.Dep. name = req.name; req = Npm c}
                in
                let formula = SemverVersion.Formula.ofDnfToCnf formula in
                (List.map ~f:(List.map ~f) formula) @ edits
              | VersionSpec.Opam formula ->
                let f (c : OpamPackageVersion.Constraint.t) =
                  {InstallManifest.Dep. name = req.name; req = Opam c}
                in
                (List.map ~f:(List.map ~f) formula) @ edits
              | VersionSpec.NpmDistTag _ ->
                failwith "cannot override opam with npm dist tag"
              | VersionSpec.Source spec ->
                [{InstallManifest.Dep. name = req.name; req = Source spec}]::edits
              end
          in
          StringMap.fold f override []
        in
        formula @ edits
      in
      InstallManifest.Dependencies.OpamFormula formula
  in

  let pkg =
    match dependencies with
    | Some override -> {
        pkg with
        InstallManifest.
        dependencies = applyNpmFormulaOverride pkg.InstallManifest.dependencies override;
      }
    | None -> pkg
  in
  let pkg =
    match devDependencies with
    | Some override -> {
        pkg with
        InstallManifest.
        devDependencies = applyNpmFormulaOverride pkg.InstallManifest.devDependencies override;
      }
    | None -> pkg
  in
  let pkg =
    match resolutions with
    | Some resolutions ->
      let resolutions =
        let f = Resolutions.add in
        StringMap.fold f resolutions Resolutions.empty
      in
      {pkg with InstallManifest.resolutions;}
    | None -> pkg
  in
  pkg

let package ~(resolution : Resolution.t) resolver =
  let open RunAsync.Syntax in
  let key = (resolution.name, resolution.resolution) in

  let ofVersion (version : Version.t) =
    match version with

    | Version.Npm version ->
      let%bind pkg =
        NpmRegistry.package
          ~name:resolution.name
          ~version
          resolver.npmRegistry ()
      in
      return (Ok pkg)
    | Version.Opam version ->
      begin match%bind
        let%bind name = RunAsync.ofRun (requireOpamName resolution.name) in
        OpamRegistry.version
          ~name
          ~version
          resolver.opamRegistry
      with
        | Some manifest ->
          OpamManifest.toInstallManifest
            ~name:resolution.name
            ~version:(Version.Opam version)
            manifest
        | None ->
          errorf "no such opam package: %a" Resolution.pp resolution
      end

    | Version.Source source ->
      packageOfSource
        ~overrides:Overrides.empty
        ~name:resolution.name
        source
        resolver
  in

  PackageCache.compute resolver.pkgCache key begin fun _ ->
    let%bind pkg =
      match resolution.resolution with
      | Version version -> ofVersion version
      | SourceOverride {source; override} ->
        let override = Override.ofJson override in
        let overrides = Overrides.(add override empty) in
        packageOfSource
          ~name:resolution.name
          ~overrides
          source
          resolver
    in
    match pkg with
    | Ok pkg ->
      let%bind pkg =
        Overrides.foldWithInstallOverrides
          ~f:applyOverride
          ~init:pkg
          pkg.overrides
        in
      return (Ok pkg)
    | err -> return err
  end

let resolveSource ~name ~(sourceSpec : SourceSpec.t) (resolver : t) =
  let open RunAsync.Syntax in

  let errorResolvingSource msg =
    errorf
      "unable to resolve %s@%a: %s"
      name SourceSpec.pp sourceSpec msg
  in

  SourceCache.compute resolver.srcCache sourceSpec begin fun _ ->
    let%lwt () = Logs_lwt.debug (fun m -> m "resolving %s@%a" name SourceSpec.pp sourceSpec) in
    let%bind source =
      match sourceSpec with
      | SourceSpec.Github {user; repo; ref; manifest;} ->
        let remote = Printf.sprintf "https://github.com/%s/%s.git" user repo in
        let%bind commit = Git.lsRemote ?ref ~remote () in
        begin match commit, ref with
        | Some commit, _ ->
          return (Source.Dist (Github {user; repo; commit; manifest;}))
        | None, Some ref ->
          if Git.isCommitLike ref
          then return (Source.Dist (Github {user; repo; commit = ref; manifest;}))
          else errorResolvingSource "cannot resolve commit"
        | None, None ->
          errorResolvingSource "cannot resolve commit"
        end

      | SourceSpec.Git {remote; ref; manifest;} ->
        let%bind commit = Git.lsRemote ?ref ~remote () in
        begin match commit, ref  with
        | Some commit, _ ->
          return (Source.Dist (Git {remote; commit; manifest;}))
        | None, Some ref ->
          if Git.isCommitLike ref
          then return (Source.Dist (Git {remote; commit = ref; manifest;}))
          else errorResolvingSource "cannot resolve commit"
        | None, None ->
          errorResolvingSource "cannot resolve commit"
        end

      | SourceSpec.NoSource ->
        return (Source.Dist NoSource)

      | SourceSpec.Archive {url; checksum = None} ->
        failwith ("archive sources without checksums are not implemented: " ^ url)
      | SourceSpec.Archive {url; checksum = Some checksum} ->
        return (Source.Dist (Archive {url; checksum}))

      | SourceSpec.LocalPath {path; manifest;} ->
        let abspath = DistPath.toPath resolver.sandbox.path path in
        if%bind Fs.exists abspath
        then return (Source.Dist (LocalPath {path; manifest;}))
        else errorf "path '%a' does not exist" Path.ppPretty abspath

    in
    Hashtbl.replace resolver.sourceSpecToSource sourceSpec source;
    return source
  end

let resolve' ~fullMetadata ~name ~spec resolver =
  let open RunAsync.Syntax in
  match spec with

  | VersionSpec.Npm _
  | VersionSpec.NpmDistTag _ ->

    let%bind resolutions =
      match%bind
        NpmRegistry.versions ~fullMetadata ~name resolver.npmRegistry ()
      with
      | Some {NpmRegistry. versions; distTags;} ->

        Hashtbl.replace resolver.npmDistTags name distTags;

        let resolutions =
          let f version =
            let version = Version.Npm version in
            {Resolution. name; resolution = Version version}
          in
          List.map ~f versions
        in

        return resolutions

      | None -> return []
    in

    let resolutions =
      let tryCheckConformsToSpec resolution =
        match resolution.Resolution.resolution with
        | Version version ->
          versionMatchesReq resolver (Req.make ~name ~spec) resolution.name version
        | SourceOverride _ -> true (* do not filter them out yet *)
      in

      resolutions
      |> List.sort ~cmp:(fun a b -> Resolution.compare b a)
      |> List.filter ~f:tryCheckConformsToSpec
    in

    return resolutions

  | VersionSpec.Opam _ ->
    let%bind resolutions =
      ResolutionCache.compute resolver.resolutionCache name begin fun () ->
        let%lwt () = Logs_lwt.debug (fun m -> m "resolving %s %a" name VersionSpec.pp spec) in
        let%bind versions =
          let%bind name = RunAsync.ofRun (requireOpamName name) in
          OpamRegistry.versions
            ?ocamlVersion:(toOpamOcamlVersion resolver.ocamlVersion)
            ~name
            resolver.opamRegistry
        in
        let f (resolution : OpamResolution.t) =
          let version = OpamResolution.version resolution in
          {Resolution. name; resolution = Version version}
        in
        return (List.map ~f versions)
      end
    in

    let resolutions =
      let tryCheckConformsToSpec resolution =
        match resolution.Resolution.resolution with
        | Version version ->
          versionMatchesReq resolver (Req.make ~name ~spec) resolution.name version
        | SourceOverride _ -> true (* do not filter them out yet *)
      in

      resolutions
      |> List.sort ~cmp:(fun a b -> Resolution.compare b a)
      |> List.filter ~f:tryCheckConformsToSpec
    in

    return resolutions

  | VersionSpec.Source sourceSpec ->
    let%bind source = resolveSource ~name ~sourceSpec resolver in
    let version = Version.Source source in
    let resolution = {
      Resolution.
      name;
      resolution = Resolution.Version version;
    } in
    return [resolution]

let resolve ?(fullMetadata=false) ~(name : string) ?(spec : VersionSpec.t option) (resolver : t) =
  let open RunAsync.Syntax in
  match Resolutions.find resolver.resolutions name with
  | Some resolution ->
    (* increment usage counter for that resolution so that we know it was used *)
    markResolutionAsUsed resolver resolution;
    return [resolution]
  | None ->
    let spec =
      match spec with
      | None ->
        if InstallManifest.isOpamPackageName name
        then VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]]
        else VersionSpec.Npm [[SemverVersion.Constraint.ANY]]
      | Some spec -> spec
    in
    resolve' ~fullMetadata ~name ~spec resolver
