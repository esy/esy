
(**
 * Execute build for the task.
 *)
let build ?(force=`ForRoot) ?(buildOnly=`ForRoot) (cfg : Config.t) (rootTask : BuildTask.t) =
  let open RunAsync.Syntax in

  let f ~allDependencies:_ ~dependencies (task : BuildTask.t) =

    let%bind () =
      dependencies
      |> List.map (fun (_, dep) -> dep)
      |> RunAsync.waitAll
    in

    let isRoot = task.id == rootTask.id in
    let installPath = Config.ConfigPath.toPath cfg task.installPath in

    let buildOnly = match buildOnly with
    | `ForRoot -> isRoot
    | `No -> false
    | `Yes -> true
    in

    let performBuild ?force () =
      let context = Printf.sprintf "building %s@%s" task.pkg.name task.pkg.version in
      let%lwt () = Logs_lwt.app(fun m -> m "%s: starting" context) in
      let%bind () = RunAsync.withContext context (
        PackageBuilder.build ?force ~buildOnly cfg task
      ) in
      let%lwt () = Logs_lwt.app(fun m -> m "%s: complete" context) in
      return ()
    in

    let performBuildIfNeeded () =
      match task.pkg.sourceType with
      | Package.SourceType.Immutable ->
        if%bind Io.exists installPath
        then return ()
        else performBuild ()
      | Package.SourceType.Development
      | Package.SourceType.Root ->
        performBuild ()
    in

    match force with
    | `ForRoot ->
      if isRoot
      then performBuild ~force:true ()
      else performBuildIfNeeded ()
    | `No ->
      performBuildIfNeeded ()
    | `Yes ->
      performBuild ~force:true ()

  in BuildTask.DependencyGraph.foldWithAllDependencies ~f rootTask
