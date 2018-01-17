
(**
 * Execute build for the task.
 *)
let build (task : BuildTask.t) =
  let f ~allDependencies:_ ~dependencies:_ _task =
    Lwt.return ()
  in
  BuildTask.DependencyGraph.fold ~f task
