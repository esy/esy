module Resolutions = Package.Resolutions
module Resolution = Package.Resolution

module PackageCache = Memoize.Make(struct
  type key = (string * Resolution.resolution)
  type value = (Package.t, string) result RunAsync.t
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
  pkgCache: PackageCache.t;
  srcCache: SourceCache.t;
  opamRegistry : OpamRegistry.t;
  npmRegistry : NpmRegistry.t;
  mutable ocamlVersion : Version.t option;
  mutable resolutions : Package.Resolutions.t;
  resolutionCache : ResolutionCache.t;

  npmDistTags : (string, SemverVersion.Version.t StringMap.t) Hashtbl.t;
  sourceSpecToSource : (SourceSpec.t, Source.t) Hashtbl.t;
  sourceToSource : (Source.t, Source.t) Hashtbl.t;
}

let make ~cfg () =
  RunAsync.return {
    cfg;
    pkgCache = PackageCache.make ();
    srcCache = SourceCache.make ();
    opamRegistry = OpamRegistry.make ~cfg ();
    npmRegistry = NpmRegistry.make ~url:cfg.Config.npmRegistry ();
    ocamlVersion = None;
    resolutions = Package.Resolutions.empty;
    resolutionCache = ResolutionCache.make ();
    npmDistTags = Hashtbl.create 500;
    sourceSpecToSource = Hashtbl.create 500;
    sourceToSource = Hashtbl.create 500;
  }

let setOCamlVersion ocamlVersion resolver =
  resolver.ocamlVersion <- Some ocamlVersion

let setResolutions resolutions resolver =
  resolver.resolutions <- resolutions

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

let versionMatchesDep (resolver : t) (dep : Package.Dep.t) name (version : Version.t) =
  let checkVersion () =
    match version, dep.Package.Dep.req with

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

let packageOfSource ~allowEmptyPackage ~name ~overrides (source : Source.t) resolver =
  let open RunAsync.Syntax in

  let readPackage ~name ~source {SourceResolver. kind; filename; data} =
    let open RunAsync.Syntax in
    match kind with
    | ManifestSpec.Filename.Esy ->
      let%bind pkg = RunAsync.ofRun (
        let open Run.Syntax in
        let%bind json = Json.parse data in
        PackageJson.packageOfJson
          ~parseResolutions:true
          ~name
          ~version:(Version.Source source)
          ~source
          json
      ) in
      return (Ok pkg)
    | ManifestSpec.Filename.Opam ->
      let%bind opamname = RunAsync.ofRun (
        match ManifestSpec.Filename.inferPackageName (kind, filename) with
        | None -> ensureOpamName name
        | Some name -> Run.return (OpamPackage.Name.of_string name)
      ) in
      let%bind manifest = RunAsync.ofRun (
        let version = OpamPackage.Version.of_string "dev" in
        OpamManifest.ofString ~name:opamname ~version data
      ) in
      OpamManifest.toPackage ~name ~version:(Version.Source source) ~source manifest
  in

  let emptyPackage ~name ~source () =
    {
      Package.
      name;
      version = Version.Source source;
      originalVersion = None;
      source = source, [];
      overrides = Package.Overrides.empty;
      dependencies = Package.Dependencies.NpmFormula [];
      devDependencies = Package.Dependencies.NpmFormula [];
      resolutions = Package.Resolutions.empty;
      opam = None;
      kind = Esy;
    }
  in

  let%bind { SourceResolver. overrides; source = resolvedSource; manifest; } =
    SourceResolver.resolve ~cfg:resolver.cfg ~overrides source
  in

  let%bind pkg =
    match manifest with
    | Some manifest ->
      readPackage ~name ~source:resolvedSource manifest
    | None ->
      if allowEmptyPackage
      then
        let pkg = emptyPackage ~name ~source:resolvedSource () in
        return (Ok pkg)
      else errorf "no manifest found at %a" Source.pp source
  in

  Hashtbl.replace resolver.sourceToSource source resolvedSource;

  match pkg with
  | Ok pkg ->
    return (Ok {
      pkg with Package.
      overrides = Package.Overrides.addMany overrides pkg.Package.overrides
    })
  | err -> return err

let package ~(resolution : Resolution.t) resolver =
  let open RunAsync.Syntax in
  let key = (resolution.name, resolution.resolution) in

  let ofVersion (version : Version.t) =
    match version with
    | Version.Source source ->
      packageOfSource
        ~allowEmptyPackage:false
        ~overrides:Package.Overrides.empty
        ~name:resolution.name
        source
        resolver

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
          OpamManifest.toPackage
            ~name:resolution.name
            ~version:(Version.Opam version)
            manifest
        | None -> error ("no such opam package: " ^ resolution.name)
      end
  in

  let applyOverride pkg override =
    let {
      Package.Overrides.
      buildType = _;
      build = _;
      install = _;
      exportedEnv = _;
      exportedEnvOverride = _;
      buildEnv = _;
      buildEnvOverride = _;

      dependencies;
      devDependencies;
      resolutions;
    } = override in

    let applyNpmFormulaOverride dependencies override =
      match dependencies with
      | Package.Dependencies.NpmFormula formula ->
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
        Package.Dependencies.NpmFormula formula
      | Package.Dependencies.OpamFormula formula ->
        (* remove all terms which we override *)
        let formula =
          let filter dep =
            match StringMap.find_opt dep.Package.Dep.name override with
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
                    {Package.Dep. name = req.name; req = Npm c}
                  in
                  let formula = SemverVersion.Formula.ofDnfToCnf formula in
                  (List.map ~f:(List.map ~f) formula) @ edits
                | VersionSpec.Opam _ ->
                  failwith "cannot override with opam version"
                | VersionSpec.NpmDistTag _ ->
                  failwith "cannot override opam with npm dist tag"
                | VersionSpec.Source spec ->
                  [{Package.Dep. name = req.name; req = Source spec}]::edits
                end
            in
            StringMap.fold f override []
          in
          formula @ edits
        in
        Package.Dependencies.OpamFormula formula
    in

    let pkg =
      match dependencies with
      | Some override -> {
          pkg with
          Package.
          dependencies = applyNpmFormulaOverride pkg.Package.dependencies override;
        }
      | None -> pkg
    in
    let pkg =
      match devDependencies with
      | Some override -> {
          pkg with
          Package.
          devDependencies = applyNpmFormulaOverride pkg.Package.devDependencies override;
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
        {pkg with Package.resolutions;}
      | None -> pkg
    in
    pkg
  in

  PackageCache.compute resolver.pkgCache key begin fun _ ->
    let pkg =
      match resolution.resolution with
      | Version version -> ofVersion version
      | SourceOverride {source; override} ->
        let overrides = Package.Overrides.(empty |> add override) in
        packageOfSource
          ~allowEmptyPackage:true
          ~name:resolution.name
          ~overrides
          source
          resolver
      in
      match%bind pkg with
      | Ok pkg ->
        let pkg =
          Package.Overrides.apply
            pkg.Package.overrides
            applyOverride
            pkg
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
          return (Source.Github {user; repo; commit; manifest;})
        | None, Some ref ->
          if Git.isCommitLike ref
          then return (Source.Github {user; repo; commit = ref; manifest;})
          else errorResolvingSource "cannot resolve commit"
        | None, None ->
          errorResolvingSource "cannot resolve commit"
        end

      | SourceSpec.Git {remote; ref; manifest;} ->
        let%bind commit = Git.lsRemote ?ref ~remote () in
        begin match commit, ref  with
        | Some commit, _ ->
          return (Source.Git {remote; commit; manifest;})
        | None, Some ref ->
          if Git.isCommitLike ref
          then return (Source.Git {remote; commit = ref; manifest;})
          else errorResolvingSource "cannot resolve commit"
        | None, None ->
          errorResolvingSource "cannot resolve commit"
        end

      | SourceSpec.NoSource ->
        return (Source.NoSource)

      | SourceSpec.Archive {url; checksum = None} ->
        failwith ("archive sources without checksums are not implemented: " ^ url)
      | SourceSpec.Archive {url; checksum = Some checksum} ->
        return (Source.Archive {url; checksum})

      | SourceSpec.LocalPath {path; manifest;} ->
        return (Source.LocalPath {path; manifest;})

      | SourceSpec.LocalPathLink {path; manifest;} ->
        return (Source.LocalPathLink {path; manifest;})
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
      let%lwt () = Logs_lwt.debug (fun m -> m "resolving %s" name) in
      let%bind {NpmRegistry. versions; distTags;} =
        match%bind
          NpmRegistry.versions ~fullMetadata ~name resolver.npmRegistry ()
        with
        | None -> errorf "no npm package %s found" name
        | Some versions -> return versions
      in

      Hashtbl.replace resolver.npmDistTags name distTags;

      let resolutions =
        let f version =
          let version = Version.Npm version in
          {Resolution. name; resolution = Version version}
        in
        List.map ~f versions
      in

      return resolutions
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
        let%lwt () = Logs_lwt.debug (fun m -> m "resolving %s" name) in
        let%bind versions =
          let%bind name = RunAsync.ofRun (requireOpamName name) in
          OpamRegistry.versions
            ?ocamlVersion:(toOpamOcamlVersion resolver.ocamlVersion)
            ~name
            resolver.opamRegistry
        in
        let f (resolution : OpamRegistry.resolution) =
          let version = Version.Opam resolution.version in
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
    print_endline "SOURCE PACKAGE";
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
  | Some resolution -> return [resolution]
  | None ->
    let spec =
      match spec with
      | None ->
        if Package.isOpamPackageName name
        then VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]]
        else VersionSpec.Npm [[SemverVersion.Constraint.ANY]]
      | Some spec -> spec
    in
    resolve' ~fullMetadata ~name ~spec resolver
