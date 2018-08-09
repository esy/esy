module Source = Package.Source
module Version = Package.Version
module SourceSpec = Package.SourceSpec
module String = Astring.String
module Override = Package.OpamOverride

module OpamPathsByVersion = Memoize.Make(struct
  type key = OpamPackage.Name.t
  type value = Path.t OpamPackage.Version.Map.t option RunAsync.t
end)

type t = {
  init : unit -> registry RunAsync.t;
  lock : Lwt_mutex.t;
  mutable registry : registry option;
}

and registry = {
  repoPath : Path.t;
  overrides : OpamOverrides.t;
  pathsCache : OpamPathsByVersion.t;
  opamCache : OpamManifest.File.Cache.t;
  archiveIndex : OpamRegistryArchiveIndex.t;
}

type resolution = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  opam: Path.t;
  url: Path.t option;
}

let packagePath ~name ~version registry =
  let name = OpamPackage.Name.to_string name in
  let version = OpamPackage.Version.to_string version in
  Path.(
    registry.repoPath
    / "packages"
    / name
    / (name ^ "." ^ version)
  )

let readOpamFileOfRegistry ~name ~version registry =
  let path = Path.(packagePath ~name ~version registry / "opam") in
  OpamManifest.File.ofPath ~cache:registry.opamCache path

let make ~cfg () =
  let init () =
    let open RunAsync.Syntax in
    let%bind repoPath =
      match cfg.Config.opamRepository with
      | Config.Local local -> return local
      | Config.Remote (remote, local) ->
        let update () =
          Logs_lwt.app (fun m -> m "checking %s for updates..." remote);%lwt
          let%bind () = Git.ShallowClone.update ~branch:"master" ~dst:local remote in
          return local
        in

        if cfg.skipRepositoryUpdate
        then (
          if%bind Fs.exists local
          then return local
          else update ()
        ) else update ()
    in

    let%bind overrides = OpamOverrides.init ~cfg () in
    let%bind archiveIndex = OpamRegistryArchiveIndex.init ~cfg () in

    return {
      repoPath;
      pathsCache = OpamPathsByVersion.make ();
      opamCache = OpamManifest.File.Cache.make ();
      overrides;
      archiveIndex;
    }
  in {init; lock = Lwt_mutex.create (); registry = None;}

let initRegistry (registry : t) =
  let init () =
    let open RunAsync.Syntax in
    match registry.registry with
    | Some v -> return v
    | None ->
      let%bind v = registry.init () in
      registry.registry <- Some v;
      return v
  in
  Lwt_mutex.with_lock registry.lock init

let getPackageVersionIndex (registry : registry) ~(name : OpamPackage.Name.t) =
  let open RunAsync.Syntax in
  let f name =
    let path = Path.(
      registry.repoPath
      / "packages"
      / OpamPackage.Name.to_string name
    ) in
    if%bind Fs.exists path
    then (
      let%bind entries = Fs.listDir path in
      let f index entry =
        let version = match String.cut ~sep:"." entry with
          | None -> OpamPackage.Version.of_string ""
          | Some (_name, version) -> OpamPackage.Version.of_string version
        in
        OpamPackage.Version.Map.add version Path.(path / entry) index
      in
      return (Some (List.fold_left ~init:OpamPackage.Version.Map.empty ~f entries))
    )
    else
      return None
  in
  OpamPathsByVersion.compute registry.pathsCache name f

let resolve
  ~(name : OpamPackage.Name.t)
  ~(version : OpamPackage.Version.t)
  (registry : registry)
  =
  let open RunAsync.Syntax in
  match%bind getPackageVersionIndex registry ~name with
  | None -> errorf "no opam package %s found" (OpamPackage.Name.to_string name)
  | Some index ->
    begin match OpamPackage.Version.Map.find_opt version index with
    | None -> errorf
        "no opam package %s@%s found"
        (OpamPackage.Name.to_string name) (OpamPackage.Version.to_string version)
    | Some packagePath ->
      let opam = Path.(packagePath / "opam") in
      let%bind url =
        let url = Path.(packagePath / "url") in
        if%bind Fs.exists url
        then return (Some url)
        else return None
      in

      return { name; opam; url; version }
    end

let versions ~(name : OpamPackage.Name.t) registry =
  let open RunAsync.Syntax in
  let%bind registry = initRegistry registry in
  match%bind getPackageVersionIndex registry ~name with
  | None -> errorf "no opam package %s found" (OpamPackage.Name.to_string name)
  | Some index ->
    let queue = LwtTaskQueue.create ~concurrency:2 () in
    let%bind resolutions =
      let getPackageVersion version () =
        resolve ~name ~version registry
      in
      index
      |> OpamPackage.Version.Map.bindings
      |> List.map ~f:(fun (version, _path) -> LwtTaskQueue.submit queue (getPackageVersion version))
      |> RunAsync.List.joinAll
    in
    return resolutions

let version ~(name : OpamPackage.Name.t) ~version registry =
  let open RunAsync.Syntax in
  let%bind registry = initRegistry registry in
  let%bind { opam = _; url; name; version } = resolve registry ~name ~version in
  let%bind pkg =
    let path = packagePath ~name ~version registry in
    let%bind opam = readOpamFileOfRegistry ~name ~version registry in
    let%bind url =
      match OpamFile.OPAM.url opam with
      | Some url -> return (Some url)
      | None ->
        begin match url with
        | Some url ->
          let%bind data = Fs.readFile url in
          return (Some (OpamFile.URL.read_from_string data))
        | None -> return None
        end
    in
    let archive = OpamRegistryArchiveIndex.find ~name ~version registry.archiveIndex in
    return {OpamManifest.name; version; opam; url; path; override = Override.empty; archive}
  in
  match%bind OpamOverrides.find ~name ~version registry.overrides with
  | None -> return (Some pkg)
  | Some override -> return (Some {pkg with OpamManifest. override})
