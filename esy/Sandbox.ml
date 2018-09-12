module Package = struct
  type t = {
    id : string;
    name : string;
    version : string;
    build : Manifest.Build.t;
    sourcePath : EsyBuildPackage.Config.Path.t;
    originPath : Path.Set.t;
    source : Manifest.Source.t option;
  }

  let pp fmt p =
    Fmt.pf fmt "Package %s" p.id

  let compare a b = String.compare a.id b.id

  module Map = Map.Make(struct
    type nonrec t = t
    let compare = compare
  end)

end

module Dependency = struct
  type t =
    (kind * Package.t, error) result
    [@@deriving ord]

  and kind =
    | Dependency
    | OptDependency
    | DevDependency
    | BuildTimeDependency

  and error =
    | InvalidDependency of { name : string; message : string; }
    | MissingDependency of { name : string; }

  let pp fmt dep =
    match dep with
    | Ok (Dependency, p) -> Fmt.pf fmt "Dependency %s" p.Package.id
    | Ok (OptDependency, p) -> Fmt.pf fmt "OptDependency %s" p.Package.id
    | Ok (DevDependency, p) -> Fmt.pf fmt "DevDependency %s" p.Package.id
    | Ok (BuildTimeDependency, p) -> Fmt.pf fmt "BuildTimeDependency %s" p.Package.id
    | Error (InvalidDependency p) -> Fmt.pf fmt "InvalidDependency %s" p.name
    | Error (MissingDependency p) -> Fmt.pf fmt "MissingDependency %s" p.name

end

type t = {
  spec : SandboxSpec.t;
  cfg : Config.t;
  buildConfig: EsyBuildPackage.Config.t;
  root : Package.t;
  dependencies : Dependency.t list Package.Map.t;
  scripts : Manifest.Scripts.t;
  env : Manifest.Env.t;
}

let dependencies pkg sandbox =
  match Package.Map.find_opt pkg sandbox.dependencies with
  | Some deps -> deps
  | None -> []

let findPackage cond sandbox =
  let rec checkPkg pkg =
    if cond pkg
    then Some pkg
    else
      match Package.Map.find_opt pkg sandbox.dependencies with
      | None -> None
      | Some deps -> checkDeps deps
  and checkDeps deps =
    match deps with
    | [] -> None
    | Ok (_, pkg)::deps ->
      begin match checkPkg pkg with
      | None -> checkDeps deps
      | Some r -> Some r
      end
    | Error _::deps -> checkDeps deps
  in
  checkPkg sandbox.root

type info = (Path.t * float) list

  let packagePathAt ?scope ~name basedir =
    match scope with
    | Some scope -> Path.(basedir / "node_modules" / scope / name)
    | None -> Path.(basedir / "node_modules" / name)

let rec resolvePackage (name : string) (basedir : Path.t) =

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

let make ~(cfg : Config.t) (spec : SandboxSpec.t) =
  let open RunAsync.Syntax in

  let manifestInfo = ref Path.Set.empty in
  let dependenciesByPackage = ref Package.Map.empty in

  let resolutionCache = Memoize.make ~size:200 () in
  let packageCache = Memoize.make ~size:200 () in

  let%bind buildConfig = RunAsync.ofBosError (
    EsyBuildPackage.Config.make
      ~storePath:cfg.storePath
      ~projectPath:spec.path
      ~localStorePath:(SandboxSpec.storePath spec)
      ~buildPath:(SandboxSpec.buildPath spec)
      ()
  ) in

  let resolvePackageCached pkgName basedir =
    let key = (pkgName, basedir) in
    let compute () = resolvePackage pkgName basedir in
    Memoize.compute resolutionCache key compute
  in

  let rec loadPackage ?name (path : Path.t) (stack : Path.t list) =

    let resolve ~ignoreCircularDep ~packagesPath (name : string) =
      match%lwt resolvePackageCached name packagesPath with
      | Ok (Some depPackagePath) ->
        if List.mem depPackagePath ~set:stack
        then
          (if ignoreCircularDep
          then Lwt.return_ok (name, `Ignored)
          else
            Lwt.return_error (name, "circular dependency"))
        else
          begin match%lwt loadPackageCached ~name depPackagePath (path :: stack) with
          | Ok pkg -> Lwt.return_ok (name, pkg)
          | Error err -> Lwt.return_error (name, (Run.formatError err))
          end
      | Ok None -> Lwt.return_ok (name, `Unresolved)
      | Error err -> Lwt.return_error (name, (Run.formatError err))
    in

    let addDependencies
      ?(skipUnresolved= false)
      ~packagesPath
      ~ignoreCircularDep
      ~make
      (dependencies : string list list)
      (prevDependencies : Dependency.t StringMap.t) =

      let%lwt dependencies =
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
            let dep = Error (Dependency.MissingDependency {name}) in
            StringMap.add name dep dependencies
        | Error (name, message) ->
          let dep = Error (Dependency.InvalidDependency {name; message;}) in
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
            ~make:(fun pkg -> Ok (DevDependency, pkg))
            deps.devDependencies
            dependencies
        else
          Lwt.return dependencies
      in
      let%lwt dependencies =
        addDependencies
          ~ignoreCircularDep
          ~packagesPath
          ~make:(fun pkg -> Ok (BuildTimeDependency, pkg))
          deps.buildTimeDependencies
          dependencies
      in
      let%lwt dependencies =
        addDependencies
          ~ignoreCircularDep
          ~packagesPath
          ~skipUnresolved:true
          ~make:(fun pkg -> Ok (OptDependency, pkg))
          deps.optDependencies
          dependencies
      in
      let%lwt dependencies =
        addDependencies
          ~ignoreCircularDep
          ~packagesPath
          ~make:(fun pkg -> Ok (Dependency, pkg))
          deps.dependencies
          dependencies
      in
      Lwt.return dependencies
    in

    let%bind manifest, forceTransient, sourcePath, packagesPath =
      let asRoot = Path.equal path spec.path in
      if asRoot
      then
        let%bind m = Manifest.ofSandboxSpec spec in
        return (Some m, false, path, SandboxSpec.nodeModulesPath spec)
      else
        let%bind forceTransient, sourcePath, manifestFilename =
          let pathToEsyLink = Path.(path / "_esylink") in
          if%bind Fs.exists pathToEsyLink
          then
            let%bind link = EsyLinkFile.ofFile pathToEsyLink in
            return (true, link.EsyLinkFile.path, link.manifest)
          else
            return (false, path, None)
        in
        let%bind m = Manifest.ofDir
          ?name
          ?manifest:manifestFilename
          sourcePath
        in
        return (m, forceTransient, sourcePath, path)
    in
    match manifest with
    | Some (manifest, originPath) ->
      manifestInfo := (Path.Set.union originPath (!manifestInfo));
      let%bind pkg =
        let build = Manifest.build manifest in

        let%lwt dependencies =
          let ignoreCircularDep = Option.isNone build in
          loadDependencies ~ignoreCircularDep ~packagesPath (Manifest.dependencies manifest)
        in

        let hasDepWithSourceTypeDevelopment =
          StringMap.exists
            (fun _k dep ->
              match dep with
                | Ok (Dependency.Dependency, pkg)
                | Ok (Dependency.BuildTimeDependency, pkg)
                | Ok (Dependency.OptDependency, pkg) ->
                  pkg.Package.build.sourceType = Manifest.SourceType.Transient
                | Ok (Dependency.DevDependency, _)
                | Error _ -> false)
            dependencies
        in

        match build with
        | Some build ->
          let sourceType =
            match hasDepWithSourceTypeDevelopment, forceTransient with
            | true, _ -> Manifest.SourceType.Transient
            | _, true -> Manifest.SourceType.Transient
            | false, false -> build.Manifest.Build.sourceType
          in

          let pkg = {
            Package.
            id = Path.toString path;
            name = Manifest.name manifest;
            version = Manifest.version manifest;
            build = {build with sourceType};
            sourcePath = EsyBuildPackage.Config.Path.ofPath buildConfig sourcePath;
            originPath;
            source = Manifest.source manifest;
          } in

          dependenciesByPackage :=
            Package.Map.add pkg (StringMap.values dependencies)
            !dependenciesByPackage;

          return (`PackageWithBuild (pkg, manifest))
        | None ->
          return (`Package dependencies)
      in
      return pkg
    | None ->
      error "unable to find manifest"

  and loadPackageCached ?name (path : Path.t) stack =
    let compute () = loadPackage ?name path stack in
    Memoize.compute packageCache (path, name) compute
  in

  match%bind loadPackageCached spec.path [] with
  | `PackageWithBuild (root, manifest) ->
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

    return ({
      spec;
      cfg;
      buildConfig;
      root;
      scripts;
      dependencies = !dependenciesByPackage;
      env;
    }, manifestInfo)

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

module Value = EsyBuildPackage.Config.Value
module Environment = EsyBuildPackage.Config.Environment
module Path = EsyBuildPackage.Config.Path

