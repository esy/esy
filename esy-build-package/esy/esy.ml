module Path = EsyCore.Path
module Package = EsyCore.Package
module BuildTask = EsyCore.BuildTask
module Environment = EsyCore.Environment
module Sandbox = EsyCore.Sandbox
module Config = EsyCore.Config
module Run = EsyCore.Run
module RunAsync = EsyCore.RunAsync
module StringMap = Map.Make(String)

let cwd = Sys.getcwd ()

let pathTerm =
  let open Cmdliner in
  let parse = Path.of_string in
  let print = Path.pp in
  Arg.conv ~docv:"PATH" (parse, print)

let resolvedPathTerm =
  let open Cmdliner in
  let parse v =
    match Path.of_string v with
    | Ok path ->
      if Path.is_abs path then
        Ok path
      else
        Ok Path.(v cwd // path |> normalize)
    | err -> err
  in
  let print = Path.pp in
  Arg.conv ~docv:"PATH" (parse, print)

let pkgPathTerm =
  let open Cmdliner in
  let doc = "Path to package." in
  Arg.(
    value
    & pos 0  (some resolvedPathTerm) None
    & info [] ~doc
  )

let configTerm =
  let open Cmdliner in
  let docs = Manpage.s_common_options in
  let prefixPath =
    let doc = "Specifies esy prefix path." in
    let env = Arg.env_var "ESY__PREFIX" ~doc in
    Arg.(
      value
      & opt (some pathTerm) None
      & info ["prefix-path"; "P"] ~env ~docs ~doc
    )
  in
  let sandboxPath =
    let doc = "Specifies esy sandbox path." in
    let env = Arg.env_var "ESY__SANDBOX" ~doc in
    Arg.(
      value
      & opt (some pathTerm) None
      & info ["sandbox-path"; "S"] ~env ~docs ~doc
    )
  in
  let parse prefixPath sandboxPath =
    EsyCore.Config.create ~prefixPath sandboxPath
  in
  Term.(const(parse) $ prefixPath $ sandboxPath)

let setupLogTerm =
  let lwt_reporter () =
    let buf_fmt ~like =
      let b = Buffer.create 512 in
      Fmt.with_buffer ~like b,
      fun () -> let m = Buffer.contents b in Buffer.reset b; m
    in
    let app, app_flush = buf_fmt ~like:Fmt.stdout in
    let dst, dst_flush = buf_fmt ~like:Fmt.stderr in
    let reporter = Logs_fmt.reporter ~app ~dst () in
    let report src level ~over k msgf =
      let k () =
        let write () = match level with
        | Logs.App -> Lwt_io.write Lwt_io.stdout (app_flush ())
        | _ -> Lwt_io.write Lwt_io.stderr (dst_flush ())
        in
        let unblock () = over (); Lwt.return_unit in
        Lwt.finalize write unblock |> Lwt.ignore_result;
        k ()
      in
      reporter.Logs.report src level ~over:(fun () -> ()) k msgf;
    in
    { Logs.report = report }
  in
  let setupLog style_renderer level =
    let style_renderer = match style_renderer with
    | None -> `None
    | Some renderer -> renderer
    in
    Fmt_tty.setup_std_outputs ~style_renderer ();
    Logs.set_level level;
    Logs.set_reporter (lwt_reporter ())
  in
  let open Cmdliner in
  Term.(const setupLog  $ Fmt_cli.style_renderer () $ Logs_cli.level  ())

let withPackageByPath cfg packagePath root f =
  let open RunAsync.Syntax in
  match packagePath with
  | Some packagePath ->
    let findByPath (pkg : Package.t) =
      let sourcePath = Config.ConfigPath.toPath cfg pkg.sourcePath in
      Path.equal sourcePath packagePath
    in begin match Package.DependencyGraph.find ~f:findByPath root with
    | None ->
      let msg = Printf.sprintf "No package found at %s" (Path.to_string packagePath) in
      error msg
    | Some pkg -> f pkg
    end
  | None -> f root

let buildEnv cfg asJson packagePath =
  let open RunAsync.Syntax in

  let%bind cfg = RunAsync.liftOfRun cfg in

  let f (pkg : Package.t) =
    let%bind task, buildEnv = RunAsync.liftOfRun (BuildTask.ofPackage pkg) in
    let header = Printf.sprintf "# Build environment for %s@%s" pkg.name pkg.version in
    let%bind source = RunAsync.liftOfRun (
      if asJson
      then
        Ok (
          task.BuildTask.env
          |> Environment.Normalized.to_yojson
          |> Yojson.Safe.pretty_to_string)
      else
        Environment.renderToShellSource ~header cfg buildEnv
    ) in
    let%lwt () = Lwt_io.print source in
    return ()
  in

  let%bind root = Sandbox.ofDir cfg in
  withPackageByPath cfg packagePath root f

let buildPlan cfg packagePath =
  let open RunAsync.Syntax in

  let%bind cfg = RunAsync.liftOfRun cfg in

  let f pkg =
    let%bind task, _buildEnv = RunAsync.liftOfRun (BuildTask.ofPackage pkg) in
    return BuildTask.ExternalFormat.(
      task
      |> ofBuildTask
      |> toString ~pretty:true
      |> print_endline
    )
  in

  let%bind root = Sandbox.ofDir cfg in
  withPackageByPath cfg packagePath root f

let buildShell cfg packagePath =
  let open RunAsync.Syntax in

  let%bind cfg = RunAsync.liftOfRun cfg in

  let f pkg =
    let%bind task, _buildEnv = RunAsync.liftOfRun (BuildTask.ofPackage pkg) in
    EsyCore.PackageBuilder.buildShell cfg task
  in

  let%bind root = Sandbox.ofDir cfg in
  withPackageByPath cfg packagePath root f

let buildPackage cfg packagePath =
  let open RunAsync.Syntax in

  let%bind cfg = RunAsync.liftOfRun cfg in

  let f pkg =
    let%bind task, _buildEnv = RunAsync.liftOfRun (BuildTask.ofPackage pkg) in
    EsyCore.Build.build ~force:`Root cfg task
  in

  let%bind root = Sandbox.ofDir cfg in
  withPackageByPath cfg packagePath root f

let build cfg command =
  let open RunAsync.Syntax in
  let%bind cfg = RunAsync.liftOfRun cfg in
  let%bind sandbox = Sandbox.ofDir cfg in
  let%bind task, _buildEnv = RunAsync.liftOfRun (BuildTask.ofPackage sandbox) in
  match command with
  | [] ->
    EsyCore.Build.build cfg task
  | command ->
    EsyCore.PackageBuilder.buildExec cfg task command

let () =
  let open Cmdliner in

  (** Prelude *)

  let exits = Term.default_exits in
  let sdocs = Manpage.s_common_options in
  let version = "v0.0.67" in

  (** CLI helpers *)

  let runCommand (cmd : unit Run.t) =
    match cmd with
    | Ok () -> `Ok ()
    | Error error ->
      let msg = Run.formatError error in
      let msg = Printf.sprintf "error, exiting...\n%s" msg in
      `Error (false, msg)
  in

  let runAsyncCommand ?(header=`Standard) (info : Cmdliner.Term.info) (cmd : unit RunAsync.t) =
    let work () =
      let%lwt () = match header with
      | `Standard -> begin match Cmdliner.Term.name info with
        | "esy" -> Logs_lwt.app (fun m -> m "esy %s" version)
        | name -> Logs_lwt.app (fun m -> m "esy %s %s" name version);
        end
      | `No -> Lwt.return ()
      in
      cmd
    in
    work () |> Lwt_main.run |> runCommand
  in

  (** Commands *)

  let defaultCommand =
    let doc = "package.json workflow for native development with Reason/OCaml" in
    let info = Term.info "esy" ~version ~doc ~sdocs ~exits in
    let cmd _cfg () = runAsyncCommand info (
      RunAsync.return ()
    ) in
    Term.(ret (const cmd $ configTerm $ setupLogTerm)), info
  in

  let buildEnvCommand =
    let doc = "Print build environment to stdout" in
    let info = Term.info "build-env" ~version ~doc ~sdocs ~exits in
    let cmd cfg asJson packagePath () =
      runAsyncCommand ~header:`No info (buildEnv cfg asJson packagePath)
    in
    let json =
      let doc = "Format output as JSON" in
      Arg.(value & flag & info ["json"]  ~doc);
    in
    Term.(ret (const cmd $ configTerm $ json $ pkgPathTerm $ setupLogTerm)), info
  in

  let buildPlanCommand =
    let doc = "Print build plan to stdout" in
    let info = Term.info "build-plan" ~version ~doc ~sdocs ~exits in
    let cmd cfg packagePath () =
      runAsyncCommand ~header:`No info (buildPlan cfg packagePath)
    in
    Term.(ret (const cmd $ configTerm $ pkgPathTerm $ setupLogTerm)), info
  in

  let buildShellCommand =
    let doc = "Enter the build shell" in
    let info = Term.info "build-shell" ~version ~doc ~sdocs ~exits in
    let cmd cfg packagePath () =
      runAsyncCommand info (buildShell cfg packagePath)
    in
    Term.(ret (const cmd $ configTerm $ pkgPathTerm $ setupLogTerm)), info
  in

  let buildPackageCommand =
    let doc = "Build specified package" in
    let info = Term.info "build-package" ~version ~doc ~sdocs ~exits in
    let cmd cfg packagePath () =
      runAsyncCommand info (buildPackage cfg packagePath)
    in
    Term.(ret (const cmd $ configTerm $ pkgPathTerm $ setupLogTerm)), info
  in

  let buildCommand =
    let doc = "Build entire sandbox" in
    let info = Term.info "build" ~version ~doc ~sdocs ~exits in
    let cmd cfg command () =
      runAsyncCommand info (build cfg command)
    in
    let commandTerm =
      Arg.(value & (pos_all string []) & (info [] ~docv:"COMMAND"))
    in
    Term.(ret (const cmd $ configTerm $ commandTerm $ setupLogTerm)), info
  in

  let makeAlias command alias =
    let term, info = command in
    let name = Term.name info in
    let doc = Printf.sprintf "An alias for $(b,%s) command" name in
    term, Term.info alias ~version ~doc ~sdocs ~exits
  in

  let bCommand = makeAlias buildCommand "b" in

  let commands = [
    (* commands *)
    buildEnvCommand;
    buildPlanCommand;
    buildShellCommand;
    buildPackageCommand;
    buildCommand;

    (* aliases *)
    bCommand;
  ] in
  Term.(exit @@ eval_choice defaultCommand commands);
