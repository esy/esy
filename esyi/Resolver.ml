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

type t = {
  cfg: Config.t;
  pkgCache: PackageCache.t;
  srcCache: SourceCache.t;
  opamRegistry : OpamRegistry.t;
  npmResolutionCache : NpmResolutionCache.t;
  opamResolutionCache : OpamResolutionCache.t;
}

let make ~cfg () =
  let open RunAsync.Syntax in
  let%bind opamRegistry = OpamRegistry.init ~cfg () in
  return {
    cfg;
    pkgCache = PackageCache.make ();
    srcCache = SourceCache.make ();
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
      | Version.Source (Git _) -> error "not implemented"
      | Version.Source (Github (user, repo, ref)) ->
        begin match%bind Package.Github.getManifest ~user ~repo ~ref () with
        | Package.PackageJson manifest ->
          return (Package.PackageJson ({ manifest with name = resolution.name }))
        | manifest -> return manifest
        end
      | Version.Source Source.NoSource -> error "no source"
      | Version.Source (Source.Archive _) -> error "not implemented"
      | Version.Npm version ->
        let%bind manifest = NpmRegistry.version ~cfg:resolver.cfg resolution.name version in
        return (Package.PackageJson manifest)
      | Version.Opam version ->
        let name = OpamFile.PackageName.ofNpmExn resolution.name in
        begin match%bind OpamRegistry.version resolver.opamRegistry ~name ~version with
          | Some manifest ->
            return (Package.Opam manifest)
          | None -> error ("no such opam package: " ^ OpamFile.PackageName.toString name)
        end
    in
    let%bind pkg = RunAsync.ofRun (Package.make ~version:resolution.version manifest) in
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
        let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" name) in
        let%bind versions = NpmRegistry.versions ~cfg:resolver.cfg name in

        let f (version, manifest) =
          let version = PackageInfo.Version.Npm version in
          let resolution = {Resolution. name; version} in

          (* precache manifest so we don't have to fetch it once more *)
          let key = (resolution.name, resolution.version) in
          PackageCache.ensureComputed resolver.pkgCache key begin fun _ ->
            Lwt.return (Package.make ~version (Package.PackageJson manifest))
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
        let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" name) in
        let%bind opamName = RunAsync.ofRun (OpamFile.PackageName.ofNpm name) in
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
          let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" (Req.toString req)) in
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

  | VersionSpec.Source (SourceSpec.Git _) ->
    let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" (Req.toString req)) in
    error "git dependencies are not supported"

  | VersionSpec.Source SourceSpec.NoSource ->
    let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" (Req.toString req)) in
    error "no source dependencies are not supported"

  | VersionSpec.Source (SourceSpec.Archive _) ->
    let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" (Req.toString req)) in
    error "archive dependencies are not supported"

  | VersionSpec.Source (SourceSpec.LocalPath p) ->
    let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" (Req.toString req)) in
    let version = Version.Source (Source.LocalPath p) in
    return [{Resolution. name; version}]
