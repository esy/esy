module ConfigPath = Config.ConfigPath

type t = {
  root : Package.t;
  scripts : Manifest.Scripts.t;
  manifestInfo : (Path.t * float) list;
}

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

let ofDir (cfg : Config.t) =
  let open RunAsync.Syntax in

  let manifestInfo = ref Path.Set.empty in

  let resolutionCache = Memoize.make ~size:200 () in

  let resolvePackageCached pkgName basedir =
    let key = (pkgName, basedir) in
    let compute _ = resolvePackage pkgName basedir in
    Memoize.compute resolutionCache key compute
  in

  let packageCache = Memoize.make ~size:200 () in

  let rec loadPackage (path : Path.t) (stack : Path.t list) =
    let addDependencies
      ?(skipUnresolved= false)
      ~ignoreCircularDep
      ~make
      (dependencies : StringSet.t)
      prevDependencies =

      let resolve (pkgName : string) =
        match%lwt resolvePackageCached pkgName path with
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

      let%lwt dependencies =
        dependencies
        |> StringSet.elements
        |> Lwt_list.map_s (fun pkgName -> resolve pkgName)
      in

      let f dependencies =
        function
        | Ok (_, `EsyPkg pkg) -> (make pkg)::dependencies
        | Ok (_, `NonEsyPkg transitiveDependencies) -> transitiveDependencies @ dependencies
        | Ok (_, `Ignored) -> dependencies
        | Ok (pkgName, `Unresolved) ->
          if skipUnresolved
          then dependencies
          else
            let dep = Package.InvalidDependency {pkgName; reason="unable to resolve package";} in
            dep::dependencies
        | Error (pkgName, reason) ->
          let dep = Package.InvalidDependency {pkgName;reason;} in
          dep::dependencies in
      Lwt.return (List.fold_left ~f ~init:prevDependencies dependencies)
    in

    let loadDependencies (manifest : Manifest.t) =
      let (>>=) = Lwt.(>>=) in
      match manifest with
      | Manifest.Esy manifest ->
        let ignoreCircularDep = Option.isNone manifest.Manifest.Esy.esy in
        Lwt.return []
        >>= addDependencies
            ~ignoreCircularDep
            ~make:(fun pkg -> Package.Dependency pkg)
            (Manifest.Esy.dependencies manifest)
        >>= addDependencies
            ~ignoreCircularDep
            ~make:(fun pkg -> Package.BuildTimeDependency pkg)
            (Manifest.Esy.buildTimeDependencies manifest)
        >>= addDependencies
            ~ignoreCircularDep
            ~skipUnresolved:true
            ~make:(fun pkg -> Package.OptDependency pkg)
            (Manifest.Esy.optDependencies manifest)
        >>= (fun dependencies ->
            if Path.equal cfg.sandboxPath path
            then
              addDependencies
                ~ignoreCircularDep ~skipUnresolved:true
                ~make:(fun pkg -> Package.DevDependency pkg)
                (Manifest.Esy.devDependencies manifest)
                dependencies
            else
              Lwt.return dependencies)
      | Manifest.Opam manifest ->
        Lwt.return []
        >>= addDependencies
            ~ignoreCircularDep:false
            ~make:(fun pkg -> Package.Dependency pkg)
            (Manifest.Opam.dependencies manifest)
        >>= addDependencies
            ~ignoreCircularDep:false
            ~skipUnresolved:true
            ~make:(fun pkg -> Package.OptDependency pkg)
            (Manifest.Opam.optDependencies manifest)
    in

    let packageOfManifest ~sourcePath (manifest : Manifest.t) pathSet =
      manifestInfo := (Path.Set.union pathSet (!manifestInfo));
      let%lwt dependencies = loadDependencies manifest in

      let hasDepWithSourceTypeDevelopment =
        List.exists
          ~f:(function
              | Package.Dependency pkg
              | Package.BuildTimeDependency pkg
              | Package.OptDependency pkg ->
                pkg.sourceType = Manifest.SourceType.Development
              | Package.DevDependency _
              | Package.InvalidDependency _ -> false)
          dependencies
      in

      match manifest with
      | Manifest.Opam manifest ->
        let pkg = Package.{
          id = Path.to_string path;
          name = Manifest.Opam.name manifest;
          version = Manifest.Opam.version manifest;
          dependencies;
          sourceType = Manifest.Opam.sourceType manifest;
          sandboxEnv = Manifest.SandboxEnv.empty;
          exportedEnv = Manifest.Opam.exportedEnv manifest;
          build = Package.OpamBuild {
            name = Manifest.Opam.opamName manifest;
            version = Manifest.Opam.version manifest;
            buildCommands = Manifest.Opam.buildCommands manifest;
            installCommands = Manifest.Opam.installCommands manifest;
            patches = Manifest.Opam.patches manifest;
            substs = Manifest.Opam.substs manifest;
            buildType = Manifest.Opam.buildType manifest;
          };
          sourcePath = ConfigPath.ofPath cfg sourcePath;
          resolution = Some ("opam:" ^ Manifest.Opam.version manifest)
        } in
        return (`EsyPkg pkg)

      | Manifest.Esy manifest ->
        begin match manifest.Manifest.Esy.esy with
        | None -> return (`NonEsyPkg dependencies)
        | Some esyManifest ->
          let sourceType =
            match hasDepWithSourceTypeDevelopment, manifest._resolved with
            | true, _
            | false, None -> Manifest.SourceType.Development
            | false, Some _ -> Manifest.SourceType.Immutable
          in
          let pkg = Package.{
            id = Path.to_string path;
            name = manifest.name;
            version = manifest.version;
            dependencies;
            sourceType;
            sandboxEnv = esyManifest.sandboxEnv;
            exportedEnv = esyManifest.exportedEnv;
            build = Package.EsyBuild {
              buildCommands = esyManifest.Manifest.EsyManifest.build;
              installCommands = esyManifest.install;
              buildType = esyManifest.buildsInSource;
            };
            sourcePath = ConfigPath.ofPath cfg sourcePath;
            resolution = manifest._resolved;
          } in
          return (`EsyPkg pkg)
        end
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

    let asRoot = Path.equal sourcePath cfg.sandboxPath in
    match%bind Manifest.ofDir ~asRoot sourcePath with
    | Some (manifest, pathSet) ->
      let%bind pkg = packageOfManifest ~sourcePath manifest pathSet in
      return (pkg, pathSet)
    | None ->
      error "unable to find manifest"

  and loadPackageCached (path : Path.t) stack =
    let compute _ = loadPackage path stack in
    Memoize.compute packageCache path compute
  in

  match%bind loadPackageCached cfg.sandboxPath [] with
  | `EsyPkg root, _ ->

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

    let%bind scripts =
      match%bind Manifest.Esy.findOfDir cfg.sandboxPath with
      | Some filename -> Manifest.Scripts.ofFile filename
      | None -> return Manifest.Scripts.empty
    in

    return {root;scripts;manifestInfo}

  | _ ->
    error "root package missing esy config"
