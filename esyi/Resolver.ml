module Resolution = struct
  type t = {
    name: string;
    version: Version.t
  } [@@deriving (eq, ord)]

  let make name version = {name; version;}

  let cmpByVersion a b =
    Version.compare a.version b.version

  let pp fmt {name; version} =
    Fmt.pf fmt "%s@%a" name Version.pp version
end

module PackageCache = Memoize.Make(struct
  type key = (string * Version.t)
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

let toOpamName name =
  match Astring.String.cut ~sep:"@opam/" name with
  | Some ("", name) -> OpamPackage.Name.of_string name
  | _ -> failwith ("invalid opam package name: " ^ name)

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

let loadPackageOfGithub ?manifest ~name ~version ~source ~user ~repo ?(ref="master") () =
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
    | Some manifest -> [ManifestFilename.toString manifest]
    | None -> ["esy.json"; "package.json"]
  in

  let rec tryFilename filenames =
    match filenames with
    | [] -> errorf "cannot find manifest at github:%s/%s#%s" user repo ref
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

let loadPackageOfPath ?manifest ~name ~version ~source (path : Path.t) =
  let open RunAsync.Syntax in

  let rec tryFilename filenames =
    match filenames with
    | [] -> errorf "cannot find manifest at %a" Path.pp path
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
    | Some manifest -> [ManifestFilename.toString manifest]
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
  opamRegistry : OpamRegistry.t;
  npmRegistry : NpmRegistry.t;
  ocamlVersion : Version.t option;
  resolutionCache : ResolutionCache.t;
}

let make ?ocamlVersion ?npmRegistry ?opamRegistry ~cfg () =
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
    opamRegistry;
    npmRegistry;
    ocamlVersion;
    resolutionCache = ResolutionCache.make ();
  }

let package ~(resolution : Resolution.t) resolver =
  let open RunAsync.Syntax in
  let key = (resolution.name, resolution.version) in
  PackageCache.compute resolver.pkgCache key begin fun _ ->
    match resolution.version with
    | Version.Source ((Source.LocalPath {path; manifest}) as source)
    | Version.Source ((Source.LocalPathLink {path; manifest}) as source) ->
      let%bind pkg = loadPackageOfPath
        ?manifest
        ~name:resolution.name
        ~version:resolution.version
        ~source:(Package.Source source)
        path
      in
      return (Ok pkg)
    | Version.Source (Git {remote; commit; manifest;} as source) ->
      Fs.withTempDir begin fun repo ->
        let%bind () = Git.clone ~dst:repo ~remote () in
        let%bind () = Git.checkout ~ref:commit ~repo () in
        let%bind pkg = loadPackageOfPath
          ?manifest
          ~name:resolution.name
          ~version:resolution.version
          ~source:(Package.Source source)
          repo
        in
        return (Ok pkg)
      end
    | Version.Source ((Github {user; repo; commit; manifest;}) as source) ->
      let%bind pkg =
        loadPackageOfGithub
          ?manifest
          ~name:resolution.name
          ~version:resolution.version
          ~source:(Package.Source source)
          ~user
          ~repo
          ~ref:commit
          ()
      in
      return (Ok pkg)
    | Version.Source Source.NoSource -> error "no source"
    | Version.Source (Source.Archive _) -> error "not implemented"
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
        let name = toOpamName resolution.name in
        OpamRegistry.version
          ~name
          ~version
          resolver.opamRegistry
      with
        | Some manifest ->
          OpamManifest.toPackage
            ~name:resolution.name
            ~version:resolution.version
            manifest
        | None -> error ("no such opam package: " ^ resolution.name)
      end
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

let resolve ?(fullMetadata=false) ~(name : string) ?(spec : VersionSpec.t option) (resolver : t) =
  let open RunAsync.Syntax in

  let spec =
    match spec with
    | None ->
      if Package.isOpamPackageName name
      then VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]]
      else VersionSpec.Npm [[SemverVersion.Constraint.ANY]]
    | Some spec -> spec
  in

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
          {Resolution. name; version}
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
      resolutions
      |> List.sort ~cmp:(fun a b -> Resolution.cmpByVersion b a)
      |> List.filter ~f:(fun r -> VersionSpec.matches ~version:r.Resolution.version spec)
    in

    return (resolutions, rewrittenSpec)

  | VersionSpec.Opam _ ->
    let%bind resolutions =
      ResolutionCache.compute resolver.resolutionCache name begin fun () ->
        let%lwt () = Logs_lwt.debug (fun m -> m "resolving %s" name) in
        let%bind versions =
          let name = toOpamName name in
          OpamRegistry.versions
            ?ocamlVersion:(toOpamOcamlVersion resolver.ocamlVersion)
            ~name
            resolver.opamRegistry
        in
        let f (resolution : OpamRegistry.resolution) =
          let version = Version.Opam resolution.version in
          {Resolution. name; version}
        in
        return (List.map ~f versions)
      end
    in

    let resolutions =
      resolutions
      |> List.sort ~cmp:(fun a b -> Resolution.cmpByVersion b a)
      |> List.filter ~f:(fun r -> VersionSpec.matches ~version:r.Resolution.version spec)
    in

    return (resolutions, None)

  | VersionSpec.Source sourceSpec ->
    let%bind source = resolveSource ~name ~sourceSpec resolver in
    let version = Version.Source source in
    let versionSpec = VersionSpec.ofVersion version in
    return ([{Resolution. name; version}], Some versionSpec)
