module VersionSpec = PackageInfo.VersionSpec
module SourceSpec = PackageInfo.SourceSpec
module Version = PackageInfo.Version
module Source = PackageInfo.Source
module Req = PackageInfo.Req

module PackageCache = Memoize.Make(struct
  type key = (string * PackageInfo.Version.t)
  type value = Package.t RunAsync.t
end)

module SourceCache = Memoize.Make(struct
  type key = SourceSpec.t
  type value = Source.t RunAsync.t
end)

module NpmCache = Memoize.Make(struct
  type key = string
  type value = (NpmVersion.Version.t * PackageJson.t) list RunAsync.t
end)

module OpamCache = Memoize.Make(struct
  type key = string
  type value = (OpamVersion.Version.t * OpamFile.ThinManifest.t) list RunAsync.t
end)

type t = {
  cfg: Config.t;
  pkgCache: PackageCache.t;
  srcCache: SourceCache.t;
  opamRegistry : OpamRegistry.t;
  npmCache : NpmCache.t;
  opamCache : OpamCache.t;
}

let make ~cfg () =
  let open RunAsync.Syntax in
  let%bind opamRegistry = OpamRegistry.init ~cfg () in
  return {
    cfg;
    pkgCache = PackageCache.make ();
    srcCache = SourceCache.make ();
    opamRegistry;
    npmCache = NpmCache.make ();
    opamCache = OpamCache.make ();
  }

let fetchPackage ~name ~version resolver =
  let open RunAsync.Syntax in
  let key = (name, version) in
  PackageCache.compute resolver.pkgCache key begin fun _ ->
    let%bind manifest =
      match version with
      | Version.Source (Source.LocalPath _) -> error "not implemented"
      | Version.Source (Git _) -> error "not implemented"
      | Version.Source (Github (user, repo, ref)) ->
        begin match%bind Package.Github.getManifest ~user ~repo ~ref () with
        | Package.PackageJson manifest ->
          return (Package.PackageJson ({ manifest with name }))
        | manifest -> return manifest
        end
      | Version.Source Source.NoSource -> error "no source"
      | Version.Source (Source.Archive _) -> error "not implemented"
      | Version.Npm version ->
        let%bind manifest = NpmRegistry.version ~cfg:resolver.cfg name version in
        return (Package.PackageJson manifest)
      | Version.Opam version ->
        let name = OpamFile.PackageName.ofNpmExn name in
        begin match%bind OpamRegistry.version resolver.opamRegistry ~name ~version with
          | Some manifest ->
            return (Package.Opam manifest)
          | None -> error ("no such opam package: " ^ OpamFile.PackageName.toString name)
        end
    in
    let%bind pkg = RunAsync.ofRun (Package.make ~version manifest) in
    return pkg
  end

let resolve ~req resolver =
  let open RunAsync.Syntax in

  let name = Req.name req in
  let spec = Req.spec req in

  match spec with

  | VersionSpec.Npm formula ->
    let%bind available =
      NpmCache.compute resolver.npmCache name begin fun name ->
        let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" name) in
        let%bind versions = NpmRegistry.versions ~cfg:resolver.cfg name in
        let () =
          let cacheManifest (version, manifest) =
            let version = PackageInfo.Version.Npm version in
            let key = (name, version) in
            PackageCache.ensureComputed resolver.pkgCache key begin fun _ ->
              Lwt.return (Package.make ~version (Package.PackageJson manifest))
            end
          in
          List.iter ~f:cacheManifest versions
        in
        return versions
      end
    in
    available
    |> List.sort ~cmp:(fun (va, _) (vb, _) -> NpmVersion.Version.compare va vb)
    |> List.filter ~f:(fun (version, _json) -> NpmVersion.Formula.DNF.matches formula ~version)
    |> List.map ~f:(
        fun (version, _json) ->
          let version = PackageInfo.Version.Npm version in
          let%bind pkg = fetchPackage ~name ~version resolver in
          return pkg
        )
    |> RunAsync.List.joinAll

  | VersionSpec.Opam formula ->
    let%bind available =
      OpamCache.compute resolver.opamCache name begin fun name ->
        let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" name) in
        let%bind opamName = RunAsync.ofRun (OpamFile.PackageName.ofNpm name) in
        let%bind info = OpamRegistry.versions resolver.opamRegistry ~name:opamName in
        return info
      end
    in

    let available =
      List.sort
        ~cmp:(fun (va, _) (vb, _) -> OpamVersion.Version.compare va vb)
        available
    in

    let matched =
      List.filter
        ~f:(fun (version, _path) -> OpamVersion.Formula.DNF.matches formula ~version)
        available
    in

    let matched =
      if matched = []
      then
        List.filter
          ~f:(fun (version, _path) -> OpamVersion.Formula.DNF.matches formula ~version)
          available
      else matched
    in

    matched
    |> List.map
        ~f:(fun (version, _path) ->
            let version = PackageInfo.Version.Opam version in
            let%bind pkg = fetchPackage ~name ~version resolver in
            return pkg)
    |> RunAsync.List.joinAll

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
      let%bind pkg = fetchPackage ~name ~version resolver in
      return [pkg]

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
    let%bind pkg = fetchPackage ~name ~version resolver in
    return [pkg]
