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

    let resolve ~ignoreCircularDep (pkgName : string) =
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

    let addDependencies
      ?(skipUnresolved= false)
      ~ignoreCircularDep
      ~make
      (dependencies : string list list)
      (prevDependencies : Package.dependency StringMap.t) =

      let rec tryResolve names =
        match names with
        | [] -> Lwt.return_ok ("ignore", `Ignored)
        | name::names ->
          if StringMap.mem name prevDependencies
          then Lwt.return_ok ("ignore", `Ignored)
          else
            begin match%lwt resolve ~ignoreCircularDep name with
            | Ok (name, `Unresolved) ->
              begin match names with
              | [] -> Lwt.return_ok (name, `Unresolved)
              | names -> tryResolve names
              end
            | res -> Lwt.return res
            end
      in

      let%lwt dependencies =
        dependencies
        |> Lwt_list.map_s tryResolve
      in

      let f dependencies =
        function
        | Ok (name, `EsyPkg pkg) ->
          let dep = make pkg in
          StringMap.add name dep dependencies
        | Ok (_, `NonEsyPkg transitiveDependencies) ->
          let f k v dependencies =
            if StringMap.mem k dependencies
            then dependencies
            else StringMap.add k v dependencies
          in
          StringMap.fold f transitiveDependencies dependencies
        | Ok (_, `Ignored) -> dependencies
        | Ok (pkgName, `Unresolved) ->
          if skipUnresolved
          then dependencies
          else
            let dep = Package.InvalidDependency {pkgName; reason="unable to resolve package";} in
            StringMap.add pkgName dep dependencies
        | Error (pkgName, reason) ->
          let dep = Package.InvalidDependency {pkgName;reason;} in
          StringMap.add pkgName dep dependencies
      in
      Lwt.return (List.fold_left ~f ~init:prevDependencies dependencies)
    in

    let loadDependencies (manifest : Manifest.t) =
      let (>>=) = Lwt.(>>=) in
      let ignoreCircularDep = Option.isNone (Manifest.buildType manifest) in
      Lwt.return StringMap.empty
      >>= addDependencies
          ~ignoreCircularDep
          ~make:(fun pkg -> Package.Dependency pkg)
          (Manifest.dependencies manifest)
      >>= addDependencies
          ~ignoreCircularDep
          ~make:(fun pkg -> Package.BuildTimeDependency pkg)
          (Manifest.buildTimeDependencies manifest)
      >>= addDependencies
          ~ignoreCircularDep
          ~skipUnresolved:true
          ~make:(fun pkg -> Package.OptDependency pkg)
          (Manifest.optDependencies manifest)
      >>= (fun dependencies ->
          if Path.equal cfg.sandboxPath path
          then
            addDependencies
              ~ignoreCircularDep ~skipUnresolved:true
              ~make:(fun pkg -> Package.DevDependency pkg)
              (Manifest.devDependencies manifest)
              dependencies
          else
            Lwt.return dependencies)
    in

    let packageOfManifest ~sourcePath (manifest : Manifest.t) pathSet =
      manifestInfo := (Path.Set.union pathSet (!manifestInfo));
      let%lwt dependencies = loadDependencies manifest in

      let hasDepWithSourceTypeDevelopment =
        StringMap.exists
          (fun _k dep ->
            match dep with
              | Package.Dependency pkg
              | Package.BuildTimeDependency pkg
              | Package.OptDependency pkg ->
                pkg.sourceType = Manifest.SourceType.Transient
              | Package.DevDependency _
              | Package.InvalidDependency _ -> false)
          dependencies
      in

      let sourceType =
        match hasDepWithSourceTypeDevelopment, Manifest.sourceType manifest with
        | true, _
        | false, Manifest.SourceType.Transient -> Manifest.SourceType.Transient
        | false, Manifest.SourceType.Immutable -> Manifest.SourceType.Immutable
      in

      match Manifest.buildType manifest with
      | Some buildType ->
        return (`EsyPkg (Package.{
          id = Path.to_string path;
          name = Manifest.name manifest;
          version = Manifest.version manifest;
          dependencies = StringMap.values dependencies;

          sourceType;
          buildType;

          sandboxEnv = Manifest.sandboxEnv manifest;
          buildEnv = Manifest.buildEnv manifest;
          exportedEnv = Manifest.exportedEnv manifest;

          buildCommands = Manifest.buildCommands manifest;
          installCommands = Manifest.installCommands manifest;

          patches = Manifest.patches manifest;
          substs = Manifest.substs manifest;

          kind = Manifest.kind manifest;

          sourcePath = Config.Path.ofPath cfg sourcePath;
          resolution = Manifest.uniqueDistributionId manifest;
        }))
      | None ->
        return (`NonEsyPkg dependencies)
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
      match%bind Manifest.findEsyManifestOfDir cfg.sandboxPath with
      | Some filename -> Manifest.Scripts.ofFile filename
      | None -> return Manifest.Scripts.empty
    in

    return {root;scripts;manifestInfo}

  | _ ->
    error "root package missing esy config"

let isSandbox = Manifest.dirHasManifest
