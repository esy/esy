
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

    let performBuild ?(force=false) () =
      let context = Printf.sprintf "building %s@%s" task.pkg.name task.pkg.version in
      RunAsync.withContext context (PackageBuilder.build ~force cfg task)
    in

    match force with
    | `No ->
      if%bind Io.exists (Config.ConfigPath.toPath cfg task.installPath) then
        return ()
      else
        performBuild ()
    | `Root when task.id == rootTask.id ->
      performBuild ~force:true ()
    | _ ->
      return ()

  in
  BuildTask.DependencyGraph.fold ~f rootTask
