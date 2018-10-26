module String = Astring.String

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
  version : OpamVersion.t option;
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
  OpamManifest.File.ofPath
    ?upgradeIfOpamVersionIsLessThan:registry.version
    ~cache:registry.opamCache
    path

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

    let%bind repo =
      let path = Path.(repoPath / "repo") in
      let%bind data = Fs.readFile path in
      let filename = OpamFile.make (OpamFilename.of_string (Path.show path)) in
      let repo = OpamFile.Repo.read_from_string ~filename data in
      return repo
    in

    return {
      version = OpamFile.Repo.opam_version repo;
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
  let f () =
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
  ?ocamlVersion
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

      let%bind available =
        let env (var : OpamVariable.Full.t) =
          let scope = OpamVariable.Full.scope var in
          let name = OpamVariable.Full.variable var in
          let v =
            let open Option.Syntax in
            let open OpamVariable in
            match scope, OpamVariable.to_string name with
            | OpamVariable.Full.Global, "preinstalled" ->
              return (bool false)
            | OpamVariable.Full.Global, "compiler"
            | OpamVariable.Full.Global, "ocaml-version" ->
              let%bind ocamlVersion = ocamlVersion in
              return (string (OpamPackage.Version.to_string ocamlVersion))
            | OpamVariable.Full.Global, _ -> None
            | OpamVariable.Full.Self, _ -> None
            | OpamVariable.Full.Package _, _ -> None
          in v
        in
        let%bind opam = readOpamFileOfRegistry ~name ~version registry in
        let formula = OpamFile.OPAM.available opam in
        let available = OpamFilter.eval_to_bool ~default:true env formula in
        return available
      in

      if available
      then return (Some { name; opam; url; version })
      else return None
    end

(* Some opam packages don't make sense for esy. *)
let isEnabledForEsy name =
  match OpamPackage.Name.to_string name with
  | "ocaml-system" -> false
  | _ -> true

let versions ?ocamlVersion ~(name : OpamPackage.Name.t) registry =
  let open RunAsync.Syntax in

  if not (isEnabledForEsy name)
  then return []
  else

  let%bind registry = initRegistry registry in
  match%bind getPackageVersionIndex registry ~name with
  | None -> return []
  | Some index ->
    let%bind resolutions =
      let getPackageVersion version =
        resolve ?ocamlVersion ~name ~version registry
      in
      RunAsync.List.mapAndJoin
        ~concurrency:2
        ~f:(fun (version, _path) -> getPackageVersion version)
        (OpamPackage.Version.Map.bindings index)
    in
    return (List.filterNone resolutions)

let version ~(name : OpamPackage.Name.t) ~version registry =
  let open RunAsync.Syntax in

  if not (isEnabledForEsy name)
  then return None
  else

  let%bind registry = initRegistry registry in
  match%bind resolve ~name ~version registry with
  | None -> return None
  | Some { opam = _; url; name; version } ->
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
      return {
        OpamManifest.name;
        version;
        opam;
        url;
        path = Some path;
        override = None;
        archive;
      }
    in
    begin match%bind OpamOverrides.find ~name ~version registry.overrides with
    | None -> return (Some pkg)
    | Some override ->
      let pkg = {pkg with OpamManifest. override = Some override;} in
      return (Some pkg)
    end
