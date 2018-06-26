module VersionSpec = PackageInfo.VersionSpec
module SourceSpec = PackageInfo.SourceSpec
module Version = PackageInfo.Version
module Source = PackageInfo.Source
module Req = PackageInfo.Req

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
  type key = (string * PackageInfo.Version.t)
  type value = Package.t RunAsync.t
end)

module SourceCache = Memoize.Make(struct
  type key = SourceSpec.t
  type value = Source.t RunAsync.t
end)

module NpmResolutionCache = Memoize.Make(struct
  type key = string
  type value = Resolution.t list RunAsync.t
end)

module OpamResolutionCache = Memoize.Make(struct
  type key = string
  type value = Resolution.t list RunAsync.t
end)

module Github = struct
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
  npmResolutionCache : NpmResolutionCache.t;
  opamResolutionCache : OpamResolutionCache.t;
}

let make ~cfg () =
  let open RunAsync.Syntax in
  let%bind opamRegistry = OpamRegistry.init ~cfg () in
  let npmRegistryQueue = LwtTaskQueue.create ~concurrency:12 () in
  return {
    cfg;
    pkgCache = PackageCache.make ();
    srcCache = SourceCache.make ();
    npmRegistryQueue;
    opamRegistry;
    npmResolutionCache = NpmResolutionCache.make ();
    opamResolutionCache = OpamResolutionCache.make ();
  }

let package ~(resolution : Resolution.t) resolver =
  let open RunAsync.Syntax in
  let key = (resolution.name, resolution.version) in
  PackageCache.compute resolver.pkgCache key begin fun _ ->

    let%bind manifest =
      match resolution.version with
      | Version.Source (Source.LocalPath _) -> error "not implemented"
      | Version.Source (Git (remote, ref) as source) ->
        Fs.withTempDir begin fun repo ->
          let%bind () = Git.clone ~dst:repo ~remote () in
          let%bind () = Git.checkout ~ref ~repo () in
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
      | Version.Source (Github (user, repo, ref)) ->
        begin match%bind Github.getManifest ~user ~repo ~ref () with
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

    let%bind pkg = RunAsync.ofRun (
      match manifest with
      | `PackageJson manifest -> Package.ofManifest ~version:resolution.version manifest
      | `Opam manifest -> Package.ofOpamManifest ~version:resolution.version manifest
    ) in

    return pkg
  end

let resolve ~req resolver =
  let open RunAsync.Syntax in

  let name = Req.name req in
  let spec = Req.spec req in

  match spec with

  | VersionSpec.Npm _ ->

    let%bind resolutions =
      NpmResolutionCache.compute resolver.npmResolutionCache name begin fun name ->
        let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" name) in
        let%bind versions = 
          LwtTaskQueue.submit
            resolver.npmRegistryQueue
            (fun () -> NpmRegistry.versions ~cfg:resolver.cfg name)
        in

        let f (version, manifest) =
          let version = PackageInfo.Version.Npm version in
          let resolution = {Resolution. name; version} in

          (* precache manifest so we don't have to fetch it once more *)
          let key = (resolution.name, resolution.version) in
          PackageCache.ensureComputed resolver.pkgCache key begin fun _ ->
            Lwt.return (Package.ofManifest ~version manifest)
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

    return resolutions

  | VersionSpec.Opam _ ->
    let%bind resolutions =
      OpamResolutionCache.compute resolver.opamResolutionCache name begin fun name ->
        let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" name) in
        let%bind opamName = RunAsync.ofRun (OpamManifest.PackageName.ofNpm name) in
        let%bind versions = OpamRegistry.versions resolver.opamRegistry ~name:opamName in
        let f (version, _) =
          let version = Version.Opam version in
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

    return resolutions

  | VersionSpec.Source (SourceSpec.Github (user, repo, ref) as srcSpec) ->
      let%bind source =
        SourceCache.compute resolver.srcCache srcSpec begin fun _ ->
          let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" (Req.toString req)) in
          let%bind ref =
            match ref with
            | Some ref -> return ref
            | None ->
              let remote =
                Printf.sprintf (("https://github.com/%s/%s")
                  [@reason.raw_literal
                    "https://github.com/%s/%s"]) user repo in
              Git.lsRemote ~remote ()
          in
          return (Source.Github (user, repo, ref))
        end
      in
      let version = Version.Source source in
      return [{Resolution. name; version}]

  | VersionSpec.Source (SourceSpec.Git (remote, ref)) ->
    let%lwt () = Logs_lwt.app (fun m -> m "resolving %s" (Req.toString req)) in
    let%bind commit = Git.lsRemote ?ref ~remote () in
    let version = Version.Source (Source.Git (remote, commit)) in
    return [{Resolution. name; version}]

  | VersionSpec.Source SourceSpec.NoSource ->
    let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" (Req.toString req)) in
    error "no source dependencies are not supported"

  | VersionSpec.Source (SourceSpec.Archive _) ->
    let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" (Req.toString req)) in
    error "archive dependencies are not supported"

  | VersionSpec.Source (SourceSpec.LocalPath p) ->
    let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" (Req.toString req)) in
    let version = Version.Source (Source.LocalPath p) in
    return [{Resolution. name; version}]
