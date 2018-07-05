module VersionSpec = Package.VersionSpec
module SourceSpec = Package.SourceSpec
module Version = Package.Version
module Source = Package.Source
module Req = Package.Req

module Resolution = struct
  type t = {
    name: string;
    version: Version.t
  }

  let cmpByVersion a b =
    Version.compare a.version b.version

  let pp fmt {name; version} =
    Fmt.pf fmt "%s@%a" name Version.pp version
end

module PackageCache = Memoize.Make(struct
  type key = (string * Package.Version.t)
  type value = Package.t RunAsync.t
end)

module SourceCache = Memoize.Make(struct
  type key = SourceSpec.t
  type value = Source.t RunAsync.t
end)

module ResolutionCache = Memoize.Make(struct
  type key = string
  type value = Resolution.t list RunAsync.t
end)

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
  resolutionCache : ResolutionCache.t;
}

let make ~cfg () =
  let open RunAsync.Syntax in
  let%bind opamRegistry = OpamRegistry.init ~cfg () in
  let npmRegistryQueue = LwtTaskQueue.create ~concurrency:25 () in
  return {
    cfg;
    pkgCache = PackageCache.make ();
    srcCache = SourceCache.make ();
    npmRegistryQueue;
    opamRegistry;
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
            let msg =
              Format.asprintf
                "cannot read manifest at %a: %s"
                Source.pp source (Run.formatError err)
            in
            error msg
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
            (fun () -> NpmRegistry.version ~cfg:resolver.cfg resolution.name version)
        in
        return (`PackageJson manifest)
      | Version.Opam version ->
        let name = OpamManifest.PackageName.ofNpmExn resolution.name in
        begin match%bind OpamRegistry.version resolver.opamRegistry ~name ~version with
          | Some manifest ->
            return (`Opam manifest)
          | None -> error ("no such opam package: " ^ OpamManifest.PackageName.toString name)
        end
    in

    let%bind pkg =
      match manifest with
      | `PackageJson manifest ->
        Manifest.toPackage
          ~name:resolution.name
          ~version:resolution.version
          manifest
      | `Opam manifest ->
        OpamRegistry.Manifest.toPackage
          ~name:resolution.name
          ~version:resolution.version
          manifest
    in

    return pkg
  end

let resolve ~req resolver =
  let open RunAsync.Syntax in

  let name = Req.name req in
  let spec = Req.spec req in

  let errorResolvingReq req msg =
    let msg = Format.asprintf "unable to resolve %a: %s" Req.pp req msg in
    error msg
  in

  match spec with

  | VersionSpec.Npm _ ->

    let%bind resolutions =
      ResolutionCache.compute resolver.resolutionCache name begin fun name ->
        let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" name) in
        let%bind versions =
          LwtTaskQueue.submit
            resolver.npmRegistryQueue
            (fun () -> NpmRegistry.versions ~cfg:resolver.cfg name)
        in

        let f (version, manifest) =
          let version = Package.Version.Npm version in
          let resolution = {Resolution. name; version} in

          (* precache manifest so we don't have to fetch it once more *)
          let key = (resolution.name, resolution.version) in
          PackageCache.ensureComputed resolver.pkgCache key begin fun _ ->
            Lwt.return (Manifest.toPackage ~version manifest)
          end;

          resolution
        in
        return (List.map ~f versions)
      end
    in

    let resolutions =
      resolutions
      |> List.sort ~cmp:Resolution.cmpByVersion
      |> List.filter ~f:(fun r -> VersionSpec.matches ~version:r.Resolution.version spec)
    in

    return (req, resolutions)

  | VersionSpec.Opam _ ->
    let%bind resolutions =
      ResolutionCache.compute resolver.resolutionCache name begin fun name ->
        let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" name) in
        let%bind opamName = RunAsync.ofRun (OpamManifest.PackageName.ofNpm name) in
        let%bind versions = OpamRegistry.versions resolver.opamRegistry ~name:opamName in
        let f (resolution : OpamRegistry.resolution) =
          let version = Version.Opam resolution.version in
          {Resolution. name; version}
        in
        return (List.map ~f versions)
      end
    in

    let resolutions =
      resolutions
      |> List.sort ~cmp:Resolution.cmpByVersion
      |> List.filter ~f:(fun r -> VersionSpec.matches ~version:r.Resolution.version spec)
    in

    return (req, resolutions)

  | VersionSpec.Source (SourceSpec.Github {user; repo; ref} as srcSpec) ->
    let%bind source = SourceCache.compute resolver.srcCache srcSpec begin fun _ ->
      let%lwt () = Logs_lwt.app (fun m -> m "resolving %s" (Req.toString req)) in
      let remote = Github.remote ~user ~repo in
      let%bind commit = Git.lsRemote ?ref ~remote () in
      match commit, ref with
      | Some commit, _ ->
        return (Source.Github {user; repo; commit})
      | None, Some ref ->
        if Git.isCommitLike ref
        then return (Source.Github {user; repo; commit = ref})
        else errorResolvingReq req "cannot resolve commit"
      | None, None ->
        errorResolvingReq req "cannot resolve commit"
    end in
    let version = Version.Source source in
    let req =
      let commit =
        match source with
        | Source.Github {commit;_} -> commit
        | _ -> assert false
      in
      let source = SourceSpec.Github {user;repo;ref = Some commit;} in
      Req.ofSpec ~name ~spec:(VersionSpec.Source source)
    in
    return (req, [{Resolution. name; version}])

  | VersionSpec.Source (SourceSpec.Git {remote; ref} as srcSpec) ->
    let%bind source = SourceCache.compute resolver.srcCache srcSpec begin fun _ ->
      let%lwt () = Logs_lwt.app (fun m -> m "resolving %s" (Req.toString req)) in
      let%bind commit = Git.lsRemote ?ref ~remote () in
      match commit, ref  with
      | Some commit, _ ->
        return (Source.Git {remote; commit})
      | None, Some ref ->
        if Git.isCommitLike ref
        then return (Source.Git {remote; commit = ref})
        else errorResolvingReq req "cannot resolve commit"
      | None, None ->
        errorResolvingReq req "cannot resolve commit"
    end in
    let version = Version.Source source in
    let req =
      let commit =
        match source with
        | Source.Git {commit;_} -> commit
        | _ -> assert false
      in
      let source = SourceSpec.Git {remote;ref = Some commit;} in
      Req.ofSpec ~name ~spec:(VersionSpec.Source source)
    in
    return (req, [{Resolution. name; version}])

  | VersionSpec.Source SourceSpec.NoSource ->
    let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" (Req.toString req)) in
    error "no source dependencies are not supported"

  | VersionSpec.Source (SourceSpec.Archive _) ->
    let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" (Req.toString req)) in
    error "archive dependencies are not supported"

  | VersionSpec.Source (SourceSpec.LocalPath p) ->
    let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" (Req.toString req)) in
    let version = Version.Source (Source.LocalPath p) in
    return (req, [{Resolution. name; version}])

  | VersionSpec.Source (SourceSpec.LocalPathLink p) ->
    let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" (Req.toString req)) in
    let version = Version.Source (Source.LocalPathLink p) in
    return (req, [{Resolution. name; version}])
