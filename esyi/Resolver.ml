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

let opamname name =
  let open RunAsync.Syntax in
  match Astring.String.cut ~sep:"@opam/" name with
  | Some ("", name) -> return (OpamPackage.Name.of_string name)
  | _ -> errorf "invalid opam package name: %s" name

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

let classifyManifest path =
  let open Result.Syntax in
  let basename = Path.basename path in
  let ext = Path.getExt path in
  match basename, ext with
  | _, ".json" -> return `PackageJson
  | _, ".opam" ->
    let name = Path.(basename (remExt path)) in
    return (`Opam (Some name))
  | "opam", "" -> return (`Opam None)
  | _ -> errorf "unknown manifest: %s" basename

let makeDummyPackage name version source =
  {
    Package.
    name;
    version;
    originalVersion = None;
    source = source, [];
    override = None;
    dependencies = Package.Dependencies.NpmFormula [];
    devDependencies = Package.Dependencies.NpmFormula [];
    opam = None;
    kind = Esy;
  }

let loadPackageOfGithub ?manifest ~allowEmptyPackage ~name ~version ~source ~user ~repo ?(ref="master") () =
  let open RunAsync.Syntax in
  let fetchFile name =
    let url =
      Printf.sprintf
        "https://raw.githubusercontent.com/%s/%s/%s/%s"
        user repo ref name
    in
    Curl.get url
  in

  let filenames =
    match manifest with
    | Some manifest -> [SandboxSpec.ManifestSpec.show manifest]
    | None -> ["esy.json"; "package.json"]
  in

  let rec tryFilename filenames =
    match filenames with
    | [] ->
      if allowEmptyPackage
      then return (makeDummyPackage name version source)
      else errorf "cannot find manifest at github:%s/%s#%s" user repo ref
    | filename::rest ->
      begin match%lwt fetchFile filename with
      | Error _ -> tryFilename rest
      | Ok data ->
        begin match classifyManifest (Path.v filename) with
        | Ok `PackageJson ->
          let%bind manifest = RunAsync.ofRun (Json.parseStringWith PackageJson.of_yojson data) in
          return (Package.ofPackageJson ~name ~version ~source manifest)
        | Ok `Opam opamname ->
          let opamname =
            match opamname with
            | None -> repo
            | Some name -> name
          in
          let%bind manifest =
            let version = OpamPackage.Version.of_string "dev" in
            let name = OpamPackage.Name.of_string opamname in
            RunAsync.ofRun (OpamManifest.ofString ~name ~version data)
          in
          begin match%bind OpamManifest.toPackage ~name ~version ~source manifest with
          | Ok pkg -> return pkg
          | Error err -> error err
          end
        | Error err -> error err
        end
      end
  in

  tryFilename filenames

let loadPackageOfPath ?manifest ~allowEmptyPackage ~name ~version ~source (path : Path.t) =
  let open RunAsync.Syntax in

  let rec tryFilename filenames =
    match filenames with
    | [] ->
      if allowEmptyPackage
      then return (makeDummyPackage name version source)
      else errorf "cannot find manifest at %a" Path.pp path
    | filename::rest ->
      let path = Path.(path / filename) in
      if%bind Fs.exists path
      then
        match classifyManifest path with
        | Ok `PackageJson ->
          let%bind manifest = PackageJson.ofFile path in
          return (Package.ofPackageJson ~name ~version ~source manifest)
        | Ok (`Opam opamname) ->
          let opamname =
            match opamname with
            | None -> Path.(basename (parent path))
            | Some name -> name
          in
          let%bind manifest =
            let version = OpamPackage.Version.of_string "dev" in
            let name = OpamPackage.Name.of_string opamname in
            OpamManifest.ofPath ~name ~version path
          in
          begin match%bind OpamManifest.toPackage ~name ~version ~source manifest with
          | Ok pkg -> return pkg
          | Error err -> error err
          end
        | Error err ->
          error err
      else
        tryFilename rest
  in
  let filenames =
    match manifest with
    | Some manifest -> [SandboxSpec.ManifestSpec.show manifest]
    | None -> [
      "esy.json";
      "package.json";
      "opam";
      Path.basename path ^ ".opam";
    ]
  in
  tryFilename filenames

type t = {
  cfg: Config.t;
  pkgCache: PackageCache.t;
  srcCache: SourceCache.t;
  resolutions : Resolutions.t;
  opamRegistry : OpamRegistry.t;
  npmRegistry : NpmRegistry.t;
  ocamlVersion : Version.t option;
  resolutionCache : ResolutionCache.t;
}

let make
  ?ocamlVersion
  ?npmRegistry
  ?opamRegistry
  ~resolutions
  ~cfg
  ()
  =
  let open RunAsync.Syntax in
  let opamRegistry =
    match opamRegistry with
    | Some opamRegistry -> opamRegistry
    | None -> OpamRegistry.make ~cfg ()
  in
  let npmRegistry =
    match npmRegistry with
    | Some npmRegistry -> npmRegistry
    | None -> NpmRegistry.make ~url:cfg.Config.npmRegistry ()
  in
  return {
    cfg;
    pkgCache = PackageCache.make ();
    srcCache = SourceCache.make ();
    resolutions;
    opamRegistry;
    npmRegistry;
    ocamlVersion;
    resolutionCache = ResolutionCache.make ();
  }

let package ~(resolution : Resolution.t) resolver =
  let open RunAsync.Syntax in
  let key = (resolution.name, resolution.resolution) in

  let ofSource ~allowEmptyPackage (source : Source.t) =
    match source with
    | LocalPath {path; manifest}
    | LocalPathLink {path; manifest} ->
      let%bind pkg = loadPackageOfPath
        ?manifest
        ~name:resolution.name
        ~version:(Version.Source source)
        ~allowEmptyPackage
        ~source
        path
      in
      return pkg
    | Git {remote; commit; manifest;} ->
      Fs.withTempDir begin fun repo ->
        let%bind () = Git.clone ~dst:repo ~remote () in
        let%bind () = Git.checkout ~ref:commit ~repo () in
        loadPackageOfPath
          ?manifest
          ~name:resolution.name
          ~version:(Version.Source source)
          ~allowEmptyPackage
          ~source
          repo
      end
    | Github {user; repo; commit; manifest;} ->
      loadPackageOfGithub
        ?manifest
        ~name:resolution.name
        ~version:(Version.Source source)
        ~allowEmptyPackage
        ~source
        ~user
        ~repo
        ~ref:commit
        ()

    | Archive _ ->
      let%bind tarballPath = FetchStorage.fetchSource ~cfg:resolver.cfg source in
      Fs.withTempDir begin fun path ->
        let%bind () = Tarball.unpack ~dst:path tarballPath in
        loadPackageOfPath
          ~name:resolution.name
          ~version:(Version.Source source)
          ~allowEmptyPackage
          ~source
          path
      end

    | NoSource ->
      return (makeDummyPackage resolution.name (Version.Source source) source)
  in

  let ofVersion (version : Version.t) =
    match version with
    | Version.Source source ->
      let%bind pkg = ofSource ~allowEmptyPackage:false source in
      return (Ok pkg)

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
        let%bind name = opamname resolution.name in
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
    let pkg = {pkg with Package. override = Some override} in
    let pkg =
      match override.Package.Override.dependencies with
      | Some dependencies -> {
          pkg with
          Package.
          dependencies = Package.Dependencies.NpmFormula dependencies
        }
      | None -> pkg
    in
    pkg
  in

  PackageCache.compute resolver.pkgCache key begin fun _ ->
    match resolution.resolution with
    | Version version -> ofVersion version
    | SourceOverride {source; override} ->
      let%bind pkg = ofSource ~allowEmptyPackage:true source in
      let pkg = applyOverride pkg override in
      return (Ok pkg)
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
  end

let resolve' ~fullMetadata ~name ~spec resolver =
  let open RunAsync.Syntax in
  match spec with

  | VersionSpec.Npm _
  | VersionSpec.NpmDistTag _ ->

    let%bind resolutions, distTags =
      let%lwt () = Logs_lwt.debug (fun m -> m "resolving %s" name) in
      let%bind {NpmRegistry. versions; distTags;} =
        match%bind
          NpmRegistry.versions ~fullMetadata ~name resolver.npmRegistry ()
        with
        | None -> errorf "no npm package %s found" name
        | Some versions -> return versions
      in

      let resolutions =
        let f version =
          let version = Version.Npm version in
          {Resolution. name; resolution = Version version}
        in
        List.map ~f versions
      in

      return (resolutions, distTags)
    in

    let rewrittenSpec =
      match spec with
      | VersionSpec.NpmDistTag (tag, _) ->
        begin match StringMap.find_opt tag distTags with
        | Some version -> Some (VersionSpec.NpmDistTag (tag, Some version))
        | None -> None
        end
      | _ -> None
    in

    let spec = Option.orDefault ~default:spec rewrittenSpec in

    let resolutions =
      let tryCheckConformsToSpec resolution =
        match resolution.Resolution.resolution with
        | Version version -> VersionSpec.matches ~version:version spec
        | SourceOverride _ -> true (* do not filter them out yet *)
      in

      resolutions
      |> List.sort ~cmp:(fun a b -> Resolution.compare b a)
      |> List.filter ~f:tryCheckConformsToSpec
    in

    return (resolutions, rewrittenSpec)

  | VersionSpec.Opam _ ->
    let%bind resolutions =
      ResolutionCache.compute resolver.resolutionCache name begin fun () ->
        let%lwt () = Logs_lwt.debug (fun m -> m "resolving %s" name) in
        let%bind versions =
          let%bind name = opamname name in
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
        | Version version -> VersionSpec.matches ~version:version spec
        | SourceOverride _ -> true (* do not filter them out yet *)
      in

      resolutions
      |> List.sort ~cmp:(fun a b -> Resolution.compare b a)
      |> List.filter ~f:tryCheckConformsToSpec
    in

    return (resolutions, None)

  | VersionSpec.Source sourceSpec ->
    let%bind source = resolveSource ~name ~sourceSpec resolver in
    let version = Version.Source source in
    let resolution = {
      Resolution.
      name;
      resolution = Resolution.Version version;
    } in
    let versionSpec = VersionSpec.ofVersion version in
    return ([resolution], Some versionSpec)

let resolve ?(fullMetadata=false) ~(name : string) ?(spec : VersionSpec.t option) (resolver : t) =
  let open RunAsync.Syntax in
  match Resolutions.find resolver.resolutions name with
  | Some resolution ->
    let spec =
      match resolution.resolution with
      | Version version ->
        VersionSpec.ofVersion version
      | SourceOverride {source; _} ->
        VersionSpec.Source (SourceSpec.ofSource source)
    in
    return ([resolution], Some spec)
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
