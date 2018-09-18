module Source = EsyInstall.Source
module Override = EsyInstall.Package.Override
module EsyLinkFile = EsyInstall.EsyLinkFile

module Package = struct
  type t = {
    id : string;
    name : string;
    version : string;
    build : Manifest.Build.t;
    originPath : Path.Set.t;
    source : Manifest.Source.t;
    sourcePath : EsyBuildPackage.Config.Path.t;
    sourceType : Manifest.SourceType.t;
  }

  let pp fmt p =
    Fmt.pf fmt "Package %s" p.id

  let compare a b = String.compare a.id b.id

  module Map = Map.Make(struct
    type nonrec t = t
    let compare = compare
  end)

end

module Dependencies = struct
  [@@@ocaml.warning "-32"]
  type t = {
    dependencies : dependency list;
    buildTimeDependencies : dependency list;
    devDependencies : dependency list;
  }
  [@@deriving ord, show]

  and dependency = (Package.t, error) result

  and error =
    | InvalidDependency of { name : string; message : string; }
    | MissingDependency of { name : string; }

  let empty = {
    dependencies = [];
    buildTimeDependencies = [];
    devDependencies = [];
  }

end

type t = {
  spec : EsyInstall.SandboxSpec.t;
  cfg : Config.t;
  buildConfig: EsyBuildPackage.Config.t;
  root : Package.t;
  dependencies : Dependencies.t Package.Map.t;
  scripts : Manifest.Scripts.t;
  env : Manifest.Env.t;
}

type info = (Path.t * float) list

let dependencies pkg sandbox =
  match Package.Map.find_opt pkg sandbox.dependencies with
  | Some deps -> deps
  | None -> Dependencies.empty

let findPackage cond sandbox =
  let rec checkPkg pkg =
    if cond pkg
    then Some pkg
    else checkDeps (dependencies pkg sandbox)

  and checkDeps deps =
    let rec check deps =
      match deps with
      | [] -> None
      | Ok pkg::deps ->
        begin match checkPkg pkg with
        | None -> check deps
        | Some r -> Some r
        end
      | Error _::deps -> check deps
    in
    check (deps.dependencies @ deps.buildTimeDependencies)

  in
  checkPkg sandbox.root

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

let applyPkgOverride (pkg : Package.t) (override : Override.t) =

  let {
    Override.
    buildType;
    build;
    install;
    exportedEnv;
    exportedEnvOverride;
    buildEnv;
    buildEnvOverride;
    dependencies = _;
  } = override in

  let pkg =
    match buildType with
    | None -> pkg
    | Some buildType -> {
        pkg with
        build = {
          pkg.build with
          buildType = buildType;
        };
      }
  in

  let pkg =
    match build with
    | None -> pkg
    | Some commands -> {
        pkg with
        build = {
          pkg.build with
          buildCommands = Manifest.Build.EsyCommands commands
        };
      }
  in

  let pkg =
    match install with
    | None -> pkg
    | Some commands -> {
        pkg with
        build = {
          pkg.build with
          installCommands = Manifest.Build.EsyCommands commands
        };
      }
  in

  let pkg =
    match exportedEnv with
    | None -> pkg
    | Some exportedEnv -> {
        pkg with
        build = {
          pkg.build with
          exportedEnv;
        };
      }
  in

  let pkg =
    match exportedEnvOverride with
    | None -> pkg
    | Some override ->
      {
        pkg with
        build = {
          pkg.build with
          exportedEnv = StringMap.Override.apply pkg.build.exportedEnv override;
        };
      }
  in

  let pkg =
    match buildEnv with
    | None -> pkg
    | Some buildEnv -> {
        pkg with
        build = {
          pkg.build with
          buildEnv;
        };
      }
  in

  let pkg =
    match buildEnvOverride with
    | None -> pkg
    | Some override ->
      {
        pkg with
        build = {
          pkg.build with
          buildEnv = StringMap.Override.apply pkg.build.buildEnv override
        };
      }
  in

  pkg


let applyDependendenciesOverride (deps : Manifest.Dependencies.t) (override : Override.t) =
  let deps =
    match override.dependencies with
    | Some dependenciesOverride ->
      let dependenciesOverride =
        let f req = [req.EsyInstall.Req.name] in
        List.map ~f dependenciesOverride
      in
      {
        deps with
        Manifest.Dependencies. dependencies = dependenciesOverride;
      }
    | None -> deps
  in
  deps

let make ~(cfg : Config.t) (spec : EsyInstall.SandboxSpec.t) =
  let open RunAsync.Syntax in

  let manifestInfo = ref Path.Set.empty in
  let dependenciesByPackage = ref Package.Map.empty in

  let resolutionCache = Memoize.make ~size:200 () in
  let packageCache = Memoize.make ~size:200 () in

  let%bind buildConfig = RunAsync.ofBosError (
    EsyBuildPackage.Config.make
      ~storePath:cfg.storePath
      ~projectPath:spec.path
      ~localStorePath:(EsyInstall.SandboxSpec.storePath spec)
      ~buildPath:(EsyInstall.SandboxSpec.buildPath spec)
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
      (dependencies : string list list) =

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
        | Ok (_, `Ignored) -> dependencies
        | Ok (_, `Package _) -> dependencies
        | Ok (_, `PackageWithBuild (pkg, _)) -> (Ok pkg)::dependencies
        | Ok (name, `Unresolved) ->
          if skipUnresolved
          then dependencies
          else
            let dep = Error (Dependencies.MissingDependency {name}) in
            dep::dependencies
        | Error (name, message) ->
          let dep = Error (Dependencies.InvalidDependency {name; message;}) in
          dep::dependencies
      in
      Lwt.return (List.fold_left ~f ~init:[] dependencies)
    in

    let loadDependencies ?override ~packagesPath ~ignoreCircularDep (deps : Manifest.Dependencies.t) =
      let deps =
        match override with
        | Some override -> applyDependendenciesOverride deps override
        | None -> deps
      in
      let%lwt devDependencies =
        if Path.equal buildConfig.EsyBuildPackage.Config.projectPath path
        then
          addDependencies
            ~ignoreCircularDep
            ~skipUnresolved:true
            ~packagesPath
            deps.devDependencies
        else Lwt.return []
      in
      let%lwt buildTimeDependencies =
        addDependencies
          ~ignoreCircularDep
          ~packagesPath
          deps.buildTimeDependencies
      in
      let%lwt optDependencies =
        addDependencies
          ~ignoreCircularDep
          ~packagesPath
          ~skipUnresolved:true
          deps.optDependencies
      in
      let%lwt dependencies =
        addDependencies
          ~ignoreCircularDep
          ~packagesPath
          deps.dependencies
      in
      Lwt.return {
        Dependencies.
        dependencies = dependencies @ optDependencies;
        buildTimeDependencies;
        devDependencies;
      }
    in

    let%bind manifest, source, sourcePath, packagesPath, override =
      let asRoot = Path.equal path spec.path in
      if asRoot
      then
        let%bind m = Manifest.ofSandboxSpec spec in
        let source = Source.LocalPathLink {path; manifest = None} in
        return (Some m, source, path, EsyInstall.SandboxSpec.nodeModulesPath spec, None)
      else
        let%bind link = EsyLinkFile.ofDir path in
        let sourcePath =
          match link.EsyLinkFile.source with
          | Source.LocalPathLink info -> info.path
          | _ -> path
        in
        let%bind m = Manifest.ofDir
          ?name
          ?manifest:(Source.manifest link.source)
          sourcePath
        in
        return (m, link.source, sourcePath, path, link.override)
    in
    match manifest, override with
    | Some (manifest, originPath), _ ->
      manifestInfo := (Path.Set.union originPath (!manifestInfo));
      let%bind pkg =
        let build = Manifest.build manifest in

        let%lwt dependencies =
          let ignoreCircularDep = Option.isNone build in
          loadDependencies ?override ~ignoreCircularDep ~packagesPath (Manifest.dependencies manifest)
        in

        let hasDepWithSourceTypeDevelopment =
          let isTransient dep =
            match dep with
            | Ok {Package. sourceType = Manifest.SourceType.Transient; _} -> true
            | Ok {Package. sourceType = Manifest.SourceType.Immutable; _} -> false
            | Error _ -> false
          in
          List.exists ~f:isTransient dependencies.dependencies
          || List.exists ~f:isTransient dependencies.buildTimeDependencies
        in

        let sourceType =
          match hasDepWithSourceTypeDevelopment, source with
          | true, _ -> Manifest.SourceType.Transient
          | false, Source.LocalPathLink _ -> Manifest.SourceType.Transient
          | false, _ -> Manifest.SourceType.Immutable
        in

        match build with
        | Some build ->

          let pkg = {
            Package.
            id = Path.toString path;
            name = Manifest.name manifest;
            version = Manifest.version manifest;
            build;
            sourcePath = EsyBuildPackage.Config.Path.ofPath buildConfig sourcePath;
            originPath;
            source;
            sourceType;
          } in

          let pkg =
            match override with
            | None -> pkg
            | Some override -> applyPkgOverride pkg override
          in

          dependenciesByPackage :=
            Package.Map.add pkg dependencies
            !dependenciesByPackage;

          return (`PackageWithBuild (pkg, Some manifest))
        | None ->
          return (`Package dependencies)
      in
      return pkg
    | None, Some override ->
      let name  =
        match name with
        | None -> "pkg"
        | Some name -> name
      in
      let%lwt dependencies =
        loadDependencies ~override ~ignoreCircularDep:false ~packagesPath
        (Manifest.Dependencies.empty)
      in
      let hasDepWithSourceTypeDevelopment =
        let isTransient dep =
          match dep with
          | Ok {Package. sourceType = Manifest.SourceType.Transient; _} -> true
          | Ok {Package. sourceType = Manifest.SourceType.Immutable; _} -> false
          | Error _ -> false
        in
        List.exists ~f:isTransient dependencies.dependencies
        || List.exists ~f:isTransient dependencies.buildTimeDependencies
      in
      let sourceType =
        match hasDepWithSourceTypeDevelopment, source with
        | true, _ -> Manifest.SourceType.Transient
        | false, Source.LocalPathLink _ -> Manifest.SourceType.Transient
        | false, _ -> Manifest.SourceType.Immutable
      in
      let pkg = {
        Package.
        id = Path.toString path;
        name;
        version = Source.show source;
        build = Manifest.Build.empty;
        sourcePath = EsyBuildPackage.Config.Path.ofPath buildConfig sourcePath;
        originPath = Path.Set.empty;
        source;
        sourceType;
      } in
      let pkg = applyPkgOverride pkg override in
      dependenciesByPackage :=
        Package.Map.add pkg dependencies
        !dependenciesByPackage;
      return (`PackageWithBuild (pkg, None))
    | None, None ->
      error "unable to find manifest"

  and loadPackageCached ?name (path : Path.t) stack =
    let compute () = loadPackage ?name path stack in
    Memoize.compute packageCache (path, name) compute
  in

  match%bind loadPackageCached spec.path [] with
  | `PackageWithBuild (_root, None) ->
    error "found no manifests for the root package"
  | `PackageWithBuild (root, Some manifest) ->
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

