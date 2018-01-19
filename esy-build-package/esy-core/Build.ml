
(**
 * Execute build for the task.
 *)
let build ?(force=`No) ?(buildOnly=`Root) (cfg : Config.t) (rootTask : BuildTask.t) =
  let open RunAsync.Syntax in

  let f ~allDependencies:_ ~dependencies (task : BuildTask.t) =

    let%bind () =
      dependencies
      |> List.map (fun (_, dep) -> dep)
      |> RunAsync.waitAll
    in

    let isRoot = task.id == rootTask.id in

    let buildOnly = match buildOnly with
    | `Root -> isRoot
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

    let installPath = Config.ConfigPath.toPath cfg task.installPath in

    match force with
    | `No ->
      begin match task.pkg.sourceType with
      | Package.SourceType.Immutable ->
        if%bind Io.exists installPath then
          return ()
        else
          performBuild ()
      | Package.SourceType.Development
      | Package.SourceType.Root ->
        performBuild ()
      end
    | `Root when isRoot ->
      performBuild ~force:true ()
    | _ ->
      return ()

  in BuildTask.DependencyGraph.fold ~f rootTask
