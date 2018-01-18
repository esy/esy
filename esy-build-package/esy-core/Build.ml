
(**
 * Execute build for the task.
 *)
let build (task : BuildTask.t) =
  let open RunAsync.Syntax in

  let buildTask (task : BuildTask.t) =
    PackageBuilder.build task
  in

  let f ~allDependencies:_ ~dependencies (task : BuildTask.t) =

    let%bind () =
      dependencies
      |> List.map (fun (_, dep) -> dep)
      |> RunAsync.waitAll
    in

    let context = Printf.sprintf "building %s@%s" task.pkg.name task.pkg.version in
    RunAsync.withContext context (buildTask task)

  in
  BuildTask.DependencyGraph.fold ~f task
