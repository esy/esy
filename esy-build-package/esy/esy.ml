module Path = EsyCore.Path

let path =
  let open Cmdliner in
  let parse = Path.of_string in
  let print = Path.pp in
  Arg.conv ~docv:"PATH" (parse, print)

module CommonOpts = struct

  type t = {
    prefixPath : Path.t;
    sandboxPath : Path.t;
  }

  let term =
    let open Cmdliner in
    let docs = Manpage.s_common_options in
    let prefixPath =
      let doc = "Specifies esy prefix path." in
      let env = Arg.env_var "ESY__PREFIX" ~doc in
      Arg.(
        value
        & opt (some path) None
        & info ["prefix-path"; "P"] ~env ~docs ~doc
      )
    in
    let sandboxPath =
      let doc = "Specifies esy sandbox path." in
      let env = Arg.env_var "ESY__SANDBOX" ~doc in
      Arg.(
        value
        & opt (some path) None
        & info ["sandbox-path"; "S"] ~env ~docs ~doc
      )
    in
    let parse prefixPath sandboxPath =
      let prefixPath = EsyLib.Option.orDefault Path.(v "~" / ".esy") prefixPath in
      let sandboxPath = EsyLib.Option.orDefault Path.(v ".") sandboxPath in
      {
        prefixPath;
        sandboxPath;
      }
    in
    Term.(
      const(parse) $ prefixPath $ sandboxPath
    );
end

let buildEnv (opts : CommonOpts.t) =
  let open EsyCore.RunAsync.Syntax in
  let%bind sandbox = EsyCore.Sandbox.ofDir opts.sandboxPath in
  let%bind _task, buildEnv = Lwt.return @@ EsyCore.BuildTask.ofPackage sandbox in
  print_endline (EsyCore.Environment.render buildEnv);
  return ()

let buildPlan (opts : CommonOpts.t) =
  let open EsyCore.RunAsync.Syntax in
  let%bind sandbox = EsyCore.Sandbox.ofDir opts.sandboxPath in
  let%bind task, _buildEnv = Lwt.return @@ EsyCore.BuildTask.ofPackage sandbox in
  return (
    task
    |> EsyCore.BuildTask.ExternalFormat.ofBuildTask
    |> EsyCore.BuildTask.ExternalFormat.to_yojson
    |> Yojson.Safe.pretty_print Format.std_formatter)

let build (opts : CommonOpts.t) =
  let open EsyCore.RunAsync.Syntax in
  let%bind sandbox = EsyCore.Sandbox.ofDir opts.sandboxPath in
  let%bind _task, _buildEnv = Lwt.return @@ EsyCore.BuildTask.ofPackage sandbox in
  return ()

let run (cmd : unit EsyCore.Run.t) =
  match cmd with
  | Ok () -> `Ok ()
  | Error error ->
    let msg = EsyCore.Run.formatError error in
    `Error (false, msg)

let runAsync (cmd : unit EsyCore.RunAsync.t) =
  cmd |> Lwt_main.run |> run

let () =
  let open Cmdliner in

  let version = "v0.0.67" in
  let exits = Term.default_exits in
  let sdocs = Manpage.s_common_options in

  let defaultCommand =
    let doc = "package.json workflow for native development with Reason/OCaml" in
    let cmd _opts = `Ok () in
    Term.(ret (const cmd $ CommonOpts.term)),
    Term.info "esy" ~version ~doc ~sdocs ~exits
  in

  let buildEnvCommand =
    let doc = "Print build environment to stdout" in
    let cmd opts = runAsync (buildEnv opts) in
    Term.(ret (const cmd $ CommonOpts.term)),
    Term.info "build-env" ~version ~doc ~sdocs ~exits
  in

  let buildPlanCommand =
    let doc = "Print build plan to stdout" in
    let cmd opts = runAsync (buildPlan opts) in
    Term.(ret (const cmd $ CommonOpts.term)),
    Term.info "build-plan" ~version ~doc ~sdocs ~exits
  in

  let buildCommand =
    let doc = "Build what needs to be build" in
    let cmd opts = runAsync (build opts) in
    Term.(ret (const cmd $ CommonOpts.term)),
    Term.info "build" ~version ~doc ~sdocs ~exits
  in

  let commands = [
    buildCommand;
    buildEnvCommand;
    buildPlanCommand;
  ] in Term.(exit @@ eval_choice defaultCommand commands);
