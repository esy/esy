
(**
 * Execute build for the task.
 *)
let build ?(force=`No) (cfg : Config.t) (rootTask : BuildTask.t) =
  let open RunAsync.Syntax in

  let f ~allDependencies:_ ~dependencies (task : BuildTask.t) =

    let%bind () =
      dependencies
      |> List.map (fun (_, dep) -> dep)
      |> RunAsync.waitAll
    in

    let isRoot = task.id == rootTask.id in

    let performBuild ?force () =
      let context = Printf.sprintf "building %s@%s" task.pkg.name task.pkg.version in
      let%lwt () = Logs_lwt.app(fun m -> m "%s: starting" context) in
      let%bind () = RunAsync.withContext context (
        PackageBuilder.build ?force ~buildOnly:isRoot cfg task
      ) in
      let%lwt () = Logs_lwt.app(fun m -> m "%s: complete" context) in
      return ()
    in

    match force with
    | `No ->
      if%bind Io.exists (Config.ConfigPath.toPath cfg task.installPath) then
        return ()
      else
        performBuild ()
    | `Root when isRoot ->
      performBuild ~force:true ()
    | _ ->
      return ()

  in
  BuildTask.DependencyGraph.fold ~f rootTask
