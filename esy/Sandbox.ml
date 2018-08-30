type t = {
  cfg : Config.t;
  buildConfig: EsyBuildPackage.Config.t;
  root : pkg;
  scripts : Manifest.Scripts.t;
  env : Manifest.Env.t;
}

and pkg = {
  id : string;
  name : string;
  version : string;
  dependencies : dependencies;
  build : Manifest.Build.t;
  sourcePath : EsyBuildPackage.Config.Path.t;
  resolution : string option;
}

and dependencies =
  dependency list

and dependency =
  | Dependency of pkg
  | OptDependency of pkg
  | DevDependency of pkg
  | BuildTimeDependency of pkg
  | InvalidDependency of {
    name: string;
    reason: [ | `Reason of string | `Missing ];
  }

type info = (Path.t * float) list

let rec resolvePackage (name : string) (basedir : Path.t) =

  let packagePathAt ?scope ~name basedir =
    match scope with
    | Some scope -> Path.(basedir / "node_modules" / scope / name)
    | None -> Path.(basedir / "node_modules" / name)
  in

  let packagePath basedir =
    match name.[0] with
    | '@' ->
      begin match String.split_on_char '/' name with
      | scope::name::[] -> packagePathAt ~name ~scope basedir
      | _ -> packagePathAt ~name basedir
      end
    | _ -> packagePathAt ~name basedir
  in

  let rec resolve basedir =
    let open RunAsync.Syntax in
    let packagePath = packagePath basedir in
    if%bind Fs.exists packagePath
    then return (Some packagePath)
    else (
      let nextBasedir = Path.parent basedir in
      if nextBasedir = basedir
      then return None
      else resolve nextBasedir
    )
  in

  resolve basedir

let make ~(cfg : Config.t) projectPath (sandbox : Project.sandbox) =
  let open RunAsync.Syntax in

  let manifestInfo = ref Path.Set.empty in

  let resolutionCache = Memoize.make ~size:200 () in
  let packageCache = Memoize.make ~size:200 () in

  let sandboxName =
    match sandbox with
    | Project.Esy { name = Some name; _ } -> name
    | Project.Esy { name = None; _ } -> "default"
    | Project.Opam _ -> "default"
    | Project.AggregatedOpam _ -> "default"
  in

  let%bind buildConfig = RunAsync.ofBosError (
    EsyBuildPackage.Config.make
      ~storePath:cfg.storePath
      ~localStorePath:Path.(projectPath / "_esy" / sandboxName / "store")
      ~projectPath
      ()
  ) in

  let resolvePackageCached pkgName basedir =
    let key = (pkgName, basedir) in
    let compute () = resolvePackage pkgName basedir in
    Memoize.compute resolutionCache key compute
  in

  let rec loadPackage (path : Path.t) (stack : Path.t list) =

    let resolve ~ignoreCircularDep ~packagesPath (pkgName : string) =
      match%lwt resolvePackageCached pkgName packagesPath with
      | Ok (Some depPackagePath) ->
        if List.mem depPackagePath ~set:stack
        then
          (if ignoreCircularDep
          then Lwt.return_ok (pkgName, `Ignored)
          else
            Lwt.return_error (pkgName, "circular dependency"))
        else begin match%lwt loadPackageCached depPackagePath (path :: stack) with
          | Ok (pkg, _) -> Lwt.return_ok (pkgName, pkg)
          | Error err -> Lwt.return_error (pkgName, (Run.formatError err))
        end
      | Ok None -> Lwt.return_ok (pkgName, `Unresolved)
      | Error err -> Lwt.return_error (pkgName, (Run.formatError err))
    in

    let addDependencies
      ?(skipUnresolved= false)
      ~packagesPath
      ~ignoreCircularDep
      ~make
      (dependencies : string list list)
      (prevDependencies : dependency StringMap.t) =

      let rec tryResolve names =
        match names with
        | [] -> Lwt.return_ok ("ignore", `Ignored)
        | name::[] ->
          resolve ~ignoreCircularDep ~packagesPath name
        | name::names ->
          begin match%lwt resolve ~ignoreCircularDep ~packagesPath name with
          | Ok (_, `Unresolved) -> tryResolve names
          | res -> Lwt.return res
          end
      in

      let%lwt dependencies =
        Lwt_list.map_s tryResolve dependencies
      in

      let f dependencies =
        function
        | Ok (name, `PackageWithBuild (pkg, _)) ->
          let dep = make pkg in
          StringMap.add name dep dependencies
        | Ok (_, `Package transitiveDependencies) ->
          let f k v dependencies =
            if StringMap.mem k dependencies
            then dependencies
            else StringMap.add k v dependencies
          in
          StringMap.fold f transitiveDependencies dependencies
        | Ok (_, `Ignored) -> dependencies
        | Ok (name, `Unresolved) ->
          if skipUnresolved
          then dependencies
          else
            let dep = InvalidDependency {name; reason = `Missing;} in
            StringMap.add name dep dependencies
        | Error (name, reason) ->
          let dep = InvalidDependency {name;reason = `Reason reason;} in
          StringMap.add name dep dependencies
      in
      Lwt.return (List.fold_left ~f ~init:prevDependencies dependencies)
    in

    let loadDependencies ~packagesPath ~ignoreCircularDep (deps : Manifest.Dependencies.t) =
      let dependencies = StringMap.empty in
      let%lwt dependencies =
        if Path.equal buildConfig.EsyBuildPackage.Config.projectPath path
        then
          addDependencies
            ~ignoreCircularDep ~skipUnresolved:true
            ~packagesPath
            ~make:(fun pkg -> DevDependency pkg)
            deps.devDependencies
            dependencies
        else
          Lwt.return dependencies
      in
      let%lwt dependencies =
        addDependencies
          ~ignoreCircularDep
          ~packagesPath
          ~make:(fun pkg -> BuildTimeDependency pkg)
          deps.buildTimeDependencies
          dependencies
      in
      let%lwt dependencies =
        addDependencies
          ~ignoreCircularDep
          ~packagesPath
          ~skipUnresolved:true
          ~make:(fun pkg -> OptDependency pkg)
          deps.optDependencies
          dependencies
      in
      let%lwt dependencies =
        addDependencies
          ~ignoreCircularDep
          ~packagesPath
          ~make:(fun pkg -> Dependency pkg)
          deps.dependencies
          dependencies
      in
      Lwt.return dependencies
    in

    let packageOfManifest ~sourcePath ~packagesPath (manifest : Manifest.t) pathSet =
      manifestInfo := (Path.Set.union pathSet (!manifestInfo));

      let build = Manifest.build manifest in

      let%lwt dependencies =
        let ignoreCircularDep = Option.isNone build in
        loadDependencies ~ignoreCircularDep ~packagesPath (Manifest.dependencies manifest)
      in

      let hasDepWithSourceTypeDevelopment =
        StringMap.exists
          (fun _k dep ->
            match dep with
              | Dependency pkg
              | BuildTimeDependency pkg
              | OptDependency pkg ->
                pkg.build.sourceType = Manifest.SourceType.Transient
              | DevDependency _
              | InvalidDependency _ -> false)
          dependencies
      in


      match build with
      | Some build ->
        let sourceType =
          match hasDepWithSourceTypeDevelopment, build.Manifest.Build.sourceType with
          | true, _
          | false, Manifest.SourceType.Transient -> Manifest.SourceType.Transient
          | false, Manifest.SourceType.Immutable -> Manifest.SourceType.Immutable
        in
        let pkg = {
          id = Path.toString path;
          name = Manifest.name manifest;
          version = Manifest.version manifest;
          dependencies = StringMap.values dependencies;
          build = {build with sourceType};
          sourcePath = EsyBuildPackage.Config.Path.ofPath buildConfig sourcePath;
          resolution = Manifest.uniqueDistributionId manifest;
        } in
        return (`PackageWithBuild (pkg, manifest))
      | None ->
        return (`Package dependencies)
    in

    let pathToEsyLink = Path.(path / "_esylink") in

    let%bind sourcePath =
      if%bind Fs.exists pathToEsyLink
      then
        let%bind path = Fs.readFile pathToEsyLink in
        return (Path.v (String.trim path))
      else
        return path
    in

    let asRoot = Path.equal sourcePath projectPath in
    let%bind manifest, packagesPath =
      if asRoot
      then
        let%bind m = Manifest.ofSandbox sandbox in
        return (Some m, Path.(projectPath / "_esy" / sandboxName))
      else
        let%bind m = Manifest.ofDir sourcePath in
        return (m, sourcePath)
    in
    match manifest with
    | Some (manifest, pathSet) ->
      let%bind pkg = packageOfManifest ~sourcePath ~packagesPath manifest pathSet in
      return (pkg, pathSet)
    | None ->
      error "unable to find manifest"

  and loadPackageCached (path : Path.t) stack =
    let compute () = loadPackage path stack in
    Memoize.compute packageCache path compute
  in

  match%bind loadPackageCached projectPath [] with
  | `PackageWithBuild (root, manifest), _ ->
    let%bind manifestInfo =
      let statPath path =
        let%bind stat = Fs.stat path in
        return (path, stat.Unix.st_mtime)
      in
      !manifestInfo
      |> Path.Set.elements
      |> List.map ~f:statPath
      |> RunAsync.List.joinAll
    in
    let%bind scripts = RunAsync.ofRun (Manifest.scripts manifest) in
    let%bind env = RunAsync.ofRun (Manifest.sandboxEnv manifest) in

    return ({cfg; buildConfig; root; scripts; env;}, manifestInfo)

  | _ ->
    error "root package missing esy config"

let isSandbox = Manifest.dirHasManifest

let initStore (path: Path.t) =
  let open RunAsync.Syntax in
  let%bind () = Fs.createDir(Path.(path / "i")) in
  let%bind () = Fs.createDir(Path.(path / "b")) in
  let%bind () = Fs.createDir(Path.(path / "s")) in
  return ()

let init sandbox =
  let open RunAsync.Syntax in
  let%bind () = initStore sandbox.buildConfig.storePath in
  let%bind () = initStore sandbox.buildConfig.localStorePath in
  let%bind () =
    let storeLinkPath = Path.(sandbox.cfg.prefixPath / Store.version) in
    if%bind Fs.exists storeLinkPath
    then return ()
    else Fs.symlink ~src:sandbox.buildConfig.storePath storeLinkPath
  in
  return ()

let compare_pkg (a : pkg) (b : pkg) = String.compare a.id b.id

let compare_dependency a b =
  match a, b with
  | Dependency a, Dependency b -> compare_pkg a b
  | OptDependency a, OptDependency b -> compare_pkg  a b
  | BuildTimeDependency a, BuildTimeDependency b -> compare_pkg a b
  | DevDependency a, DevDependency b -> compare_pkg a b
  | InvalidDependency a, InvalidDependency b -> String.compare a.name b.name
  | Dependency _, _ -> 1
  | OptDependency _, Dependency _ -> -1
  | OptDependency _, _ -> 1
  | BuildTimeDependency _, Dependency _ -> -1
  | BuildTimeDependency _, OptDependency _ -> -1
  | BuildTimeDependency _, _ -> 1
  | DevDependency _, Dependency _ -> -1
  | DevDependency _, OptDependency _ -> -1
  | DevDependency _, BuildTimeDependency _ -> -1
  | DevDependency _, _ -> 1
  | InvalidDependency _, _ -> -1

let pp_dependency fmt dep =
  match dep with
  | Dependency p -> Fmt.pf fmt "Dependency %s" p.id
  | OptDependency p -> Fmt.pf fmt "OptDependency %s" p.id
  | DevDependency p -> Fmt.pf fmt "DevDependency %s" p.id
  | BuildTimeDependency p -> Fmt.pf fmt "BuildTimeDependency %s" p.id
  | InvalidDependency p -> Fmt.pf fmt "InvalidDependency %s" p.name

let packageOf (dep : dependency) = match dep with
| Dependency pkg
| OptDependency pkg
| DevDependency pkg
| BuildTimeDependency pkg -> Some pkg
| InvalidDependency _ -> None

module PackageMap = Map.Make(struct
  type t = pkg
  let compare = compare_pkg
end)

module PackageGraph = DependencyGraph.Make(struct

  type t = pkg

  let compare = compare_pkg

  module Dependency = struct
    type t = dependency
    let compare = compare_dependency
  end

  let id (pkg : t) = pkg.id

  let traverse pkg =
    let f acc dep = match dep with
      | Dependency pkg
      | OptDependency pkg
      | DevDependency pkg
      | BuildTimeDependency pkg -> (pkg, dep)::acc
      | InvalidDependency _ -> acc
    in
    pkg.dependencies
    |> List.fold_left ~f ~init:[]
    |> List.rev

end)

module DependencySet = Set.Make(struct
  type t = dependency
  let compare = compare_dependency
end)

module DependencyMap = Map.Make(struct
  type t = dependency
  let compare = compare_dependency
end)

module Value = EsyBuildPackage.Config.Value
module Environment = EsyBuildPackage.Config.Environment
module Path = EsyBuildPackage.Config.Path

