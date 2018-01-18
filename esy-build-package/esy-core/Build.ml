
(**
 * Execute build for the task.
 *)
let build (task : BuildTask.t) =
  let open RunAsync.Syntax in

  let command = (
    "./_build/default/esy-build-package/esyBuildPackage.bc",
    [|"build"; "--build"; "-";|]
) in

  let buildTask (task : BuildTask.t) =

    let f process =
      let%lwt () =
        task
        |> BuildTask.ExternalFormat.ofBuildTask
        |> BuildTask.ExternalFormat.to_yojson
        |> Yojson.Safe.to_string
        |> Lwt_io.write process#stdin
      in
      let%lwt () = Lwt_io.flush process#stdin in
      let%lwt () = Lwt_io.close process#stdin in
      match%lwt process#status with
      | Unix.WEXITED 0 -> return ()
      | _ -> error "build process exited with an error"
    in
    try%lwt
      Lwt_process.with_process_out
        ~stderr:(`FD_copy Unix.stderr)
        ~stdout:(`FD_copy Unix.stdout)
        command f
    with
    | _ -> error "some error"
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
