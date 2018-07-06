module VersionSpec = Package.VersionSpec
module SourceSpec = Package.SourceSpec
module Version = Package.Version
module Source = Package.Source
module Req = Package.Req
module DepFormula = Package.DepFormula

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

let toOpamName name =
  match Astring.String.cut ~sep:"@opam/" name with
  | Some ("", name) -> OpamPackage.Name.of_string name
  | _ -> failwith ("invalid opam package name: " ^ name)

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
        begin match%bind
          let name = toOpamName resolution.name in
          OpamRegistry.version resolver.opamRegistry ~name ~version
        with
          | Some manifest ->
            return (`Opam manifest)
          | None -> error ("no such opam package: " ^ resolution.name)
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

let resolveSource ~name ~(sourceSpec : SourceSpec.t) (resolver : t) =
  let open RunAsync.Syntax in

  let errorResolvingSource msg =
    let msg =
      Format.asprintf
        "unable to resolve %s@%a: %s"
        name SourceSpec.pp sourceSpec msg
    in
    error msg
  in

  SourceCache.compute resolver.srcCache sourceSpec begin fun _ ->
    let%lwt () = Logs_lwt.app (fun m -> m "resolving %s@%a" name SourceSpec.pp sourceSpec) in
    match sourceSpec with
    | SourceSpec.Github {user; repo; ref} ->
      let%lwt () = Logs_lwt.app (fun m -> m "resolving %s@%a" name SourceSpec.pp sourceSpec) in
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
      let%lwt () = Logs_lwt.app (fun m -> m "resolving %s@%a" name SourceSpec.pp sourceSpec) in
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

    | SourceSpec.Archive (url, None) ->
      (* TODO: acquire checksum *)
      return (Source.Archive (url, "fakechecksum"))
    | SourceSpec.Archive (url, Some checksum) ->
      return (Source.Archive (url, checksum))

    | SourceSpec.LocalPath p ->
      return (Source.LocalPath p)

    | SourceSpec.LocalPathLink p ->
      return (Source.LocalPathLink p)
  end

let resolve ~(name : string) ~(formula : DepFormula.t) (resolver : t) =
  let open RunAsync.Syntax in

  match formula with

  | DepFormula.Npm _ ->

    let%bind resolutions =
      ResolutionCache.compute resolver.resolutionCache name begin fun name ->
        let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" name) in
        let%bind versions =
          match%bind
            LwtTaskQueue.submit
              resolver.npmRegistryQueue
              (fun () -> NpmRegistry.versions ~cfg:resolver.cfg name)
          with
          | [] ->
            let msg = Format.asprintf "no npm package %s found" name in
            error msg
          | versions -> return versions
        in

        let f (version, manifest) =
          let version = Package.Version.Npm version in
          let resolution = {Resolution. name; version} in

          (* precache manifest so we don't have to fetch it once more *)
          let key = (resolution.name, resolution.version) in
          PackageCache.ensureComputed resolver.pkgCache key begin fun _ ->
            Manifest.toPackage ~version manifest
          end;

          resolution
        in
        return (List.map ~f versions)
      end
    in

    let resolutions =
      resolutions
      |> List.sort ~cmp:Resolution.cmpByVersion
      |> List.filter ~f:(fun r -> DepFormula.matches ~version:r.Resolution.version formula)
    in

    return resolutions

  | DepFormula.Opam _ ->
    let%bind resolutions =
      ResolutionCache.compute resolver.resolutionCache name begin fun name ->
        let%lwt () = Logs_lwt.debug (fun m -> m "Resolving %s" name) in
        let%bind versions =
          match%bind
            let name = toOpamName name in
            OpamRegistry.versions ~name resolver.opamRegistry
          with
          | [] ->
            let msg = Format.asprintf "no opam package %s found" name in
            error msg
          | versions -> return versions
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
      |> List.sort ~cmp:Resolution.cmpByVersion
      |> List.filter ~f:(fun r -> DepFormula.matches ~version:r.Resolution.version formula)
    in

    return resolutions

  | DepFormula.Source sourceSpec ->
    let%bind source = resolveSource ~name ~sourceSpec resolver in
    let version = Version.Source source in
    return [{Resolution. name; version}]
