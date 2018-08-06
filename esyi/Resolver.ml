module VersionSpec = Package.VersionSpec
module SourceSpec = Package.SourceSpec
module Version = Package.Version
module Source = Package.Source
module Req = Package.Req

module Resolution = struct
  type t = {
    name: string;
    version: Version.t
  } [@@deriving (eq, ord)]

  let cmpByVersion a b =
    Version.compare a.version b.version

  let pp fmt {name; version} =
    Fmt.pf fmt "%s@%a" name Version.pp version
end

module PackageCache = Memoize.Make(struct
  type key = (string * Package.Version.t)
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
  | Some (Package.Version.Npm { major; minor; patch; _ }) ->
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
    Some (OpamVersion.Version.parseExn v)
  | Some (Package.Version.Opam v) -> Some v
  | Some (Package.Version.Source _) -> None
  | None -> None

module Github = struct

  let remote ~user ~repo =
    Printf.sprintf "https://github.com/%s/%s.git" user repo

  let getManifest ~user ~repo ?(ref="master") () =
    let open RunAsync.Syntax in
    let fetchFile name =
      let url =
        "https://raw.githubusercontent.com"
        ^ "/" ^ user
        ^ "/" ^ repo
        ^ "/" ^ ref (* TODO: resolve default ref against GH instead *)
        ^ "/" ^ name
      in
      Curl.get url
    in
    match%lwt fetchFile "esy.json" with
    | Ok data ->
      let%bind packageJson =
        RunAsync.ofRun (Json.parseStringWith Manifest.of_yojson data)
      in
      return (`PackageJson packageJson)
    | Error _ ->
      begin match%lwt fetchFile "package.json" with
      | Ok text ->
        let%bind packageJson =
          RunAsync.ofRun (Json.parseStringWith Manifest.of_yojson text)
        in
        return (`PackageJson packageJson)
      | Error _ ->
        error "no manifest found"
      end
end

type t = {
  cfg: Config.t;
  pkgCache: PackageCache.t;
  srcCache: SourceCache.t;
  npmRegistryQueue : LwtTaskQueue.t;
  opamRegistry : OpamRegistry.t;
  ocamlVersion : Package.Version.t option;
  resolutionCache : ResolutionCache.t;
}

let make ?ocamlVersion ?opamRegistry ~cfg () =
  let open RunAsync.Syntax in
  let opamRegistry =
    match opamRegistry with
    | Some opamRegistry -> opamRegistry
    | None -> OpamRegistry.make ~cfg ()
  in
  let npmRegistryQueue = LwtTaskQueue.create ~concurrency:25 () in
  return {
    cfg;
    pkgCache = PackageCache.make ();
    srcCache = SourceCache.make ();
    npmRegistryQueue;
    opamRegistry;
    ocamlVersion;
    resolutionCache = ResolutionCache.make ();
  }

let package ~(resolution : Resolution.t) resolver =
  let open RunAsync.Syntax in
  let key = (resolution.name, resolution.version) in
  PackageCache.compute resolver.pkgCache key begin fun _ ->

    let%bind manifest =
      match resolution.version with

      | Version.Source (Source.LocalPath path)
      | Version.Source (Source.LocalPathLink path) ->
        let%bind manifest = Manifest.ofDir path in
        return (`PackageJson manifest)

      | Version.Source (Git {remote; commit} as source) ->
        Fs.withTempDir begin fun repo ->
          let%bind () = Git.clone ~dst:repo ~remote () in
          let%bind () = Git.checkout ~ref:commit ~repo () in
          match%lwt Manifest.ofDir repo with
          | Ok manifest ->
            let manifest = {manifest with name = resolution.name} in
            return (`PackageJson manifest)
          | Error err ->
            errorf
              "cannot read manifest at %a: %s"
              Source.pp source (Run.formatError err)
        end
      | Version.Source (Github {user; repo; commit}) ->
        begin match%bind Github.getManifest ~user ~repo ~ref:commit () with
        | `PackageJson manifest ->
          return (`PackageJson (Manifest.{ manifest with name = resolution.name }))
        end
      | Version.Source Source.NoSource -> error "no source"
      | Version.Source (Source.Archive _) -> error "not implemented"
      | Version.Npm version ->
        let%bind manifest =
          LwtTaskQueue.submit
            resolver.npmRegistryQueue
            (NpmRegistry.version ~cfg:resolver.cfg ~name:resolution.name ~version)
        in
        return (`PackageJson manifest)
      | Version.Opam version ->
        begin match%bind
          let name = toOpamName resolution.name in
          OpamRegistry.version
            ~name
            ~version
            resolver.opamRegistry
        with
          | Some manifest ->
            return (`Opam manifest)
          | None -> error ("no such opam package: " ^ resolution.name)
        end
    in

    let%bind pkg =
      match manifest with
      | `PackageJson manifest ->
        let%bind pkg =
          Manifest.toPackage
            ~name:resolution.name
            ~version:resolution.version
            manifest
        in
        return (Ok pkg)
      | `Opam manifest ->
        OpamRegistry.Manifest.toPackage
          ~name:resolution.name
          ~version:resolution.version
          manifest
    in

    return pkg
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
    | SourceSpec.Github {user; repo; ref} ->
      let remote = Github.remote ~user ~repo in
      let%bind commit = Git.lsRemote ?ref ~remote () in
      begin match commit, ref with
      | Some commit, _ ->
        return (Source.Github {user; repo; commit})
      | None, Some ref ->
        if Git.isCommitLike ref
        then return (Source.Github {user; repo; commit = ref})
        else errorResolvingSource "cannot resolve commit"
      | None, None ->
        errorResolvingSource "cannot resolve commit"
      end

    | SourceSpec.Git {remote; ref} ->
      let%bind commit = Git.lsRemote ?ref ~remote () in
      begin match commit, ref  with
      | Some commit, _ ->
        return (Source.Git {remote; commit})
      | None, Some ref ->
        if Git.isCommitLike ref
        then return (Source.Git {remote; commit = ref})
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

    | SourceSpec.LocalPath p ->
      return (Source.LocalPath p)

    | SourceSpec.LocalPathLink p ->
      return (Source.LocalPathLink p)
  end

let resolve ?(fullMetadata=false) ~(name : string) ?(spec : VersionSpec.t option) (resolver : t) =
  let open RunAsync.Syntax in

  let spec =
    match spec with
    | None ->
      if Package.isOpamPackageName name
      then VersionSpec.Opam [[OpamVersion.Constraint.ANY]]
      else VersionSpec.Npm [[SemverVersion.Constraint.ANY]]
    | Some spec -> spec
  in

  match spec with

  | VersionSpec.Npm _ ->

    let%bind resolutions =
      ResolutionCache.compute resolver.resolutionCache name begin fun name ->
        let%lwt () = Logs_lwt.debug (fun m -> m "resolving %s" name) in
        let%bind versions =
          match%bind
            LwtTaskQueue.submit
              resolver.npmRegistryQueue
              (NpmRegistry.versions ~fullMetadata ~cfg:resolver.cfg ~name)
          with
          | [] -> errorf "no npm package %s found" name
          | versions -> return versions
        in

        let f (version, manifest) =
          let version = Package.Version.Npm version in
          let resolution = {Resolution. name; version} in

          (* precache manifest so we don't have to fetch it once more *)
          let key = (resolution.name, resolution.version) in
          PackageCache.ensureComputed resolver.pkgCache key begin fun _ ->
            let%bind pkg = Manifest.toPackage ~version manifest in
            return (Ok pkg)
          end;

          resolution
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

  | VersionSpec.Opam _ ->
    let%bind resolutions =
      ResolutionCache.compute resolver.resolutionCache name begin fun name ->
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
