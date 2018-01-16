let buildEnv sandbox =
  let open EsyCore.Run.Syntax in
  let%bind _task, buildEnv = EsyCore.BuildTask.ofPackage sandbox in
  print_endline (EsyCore.Environment.render buildEnv);
  return ()

let main () =
  let open EsyCore.RunAsync.Syntax in
  let%bind sandbox = EsyCore.Sandbox.ofDir (EsyCore.Path.v ".") in
  Lwt.return (buildEnv sandbox)

let () =
  match Lwt_main.run (main ()) with
  | Ok () ->
    exit 0
  | Error err ->
    print_endline (EsyCore.Run.formatError err);
    exit 1
