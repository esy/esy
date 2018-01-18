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
    EsyCore.Build.build ~force:`Root cfg task
  | command ->
    EsyCore.PackageBuilder.buildExec cfg task command

let run (cmd : unit Run.t) =
  match cmd with
  | Ok () -> `Ok ()
  | Error error ->
    let msg = Run.formatError error in
    let msg = Printf.sprintf "fatal error, see below\n%s" msg in
    `Error (false, msg)

let runAsync (cmd : unit RunAsync.t) =
  cmd |> Lwt_main.run |> run

let () =
  let open Cmdliner in

  let version = "v0.0.67" in
  let exits = Term.default_exits in
  let sdocs = Manpage.s_common_options in

  let defaultCommand =
    let doc = "package.json workflow for native development with Reason/OCaml" in
    let cmd _opts = `Ok () in
    (
      Term.(ret (const cmd $ configTerm)),
      Term.info "esy" ~version ~doc ~sdocs ~exits
    )
  in

  let buildEnvCommand =
    let doc = "Print build environment to stdout" in
    let cmd cfg asJson packagePath =
      runAsync (buildEnv cfg asJson packagePath)
    in
    let json =
      let doc = "Format output as JSON" in
      Arg.(value & flag & info ["json"]  ~doc);
    in
    Term.(ret (const cmd $ configTerm $ json $ pkgPathTerm)),
    Term.info "build-env" ~version ~doc ~sdocs ~exits
  in

  let buildPlanCommand =
    let doc = "Print build plan to stdout" in
    let cmd cfg packagePath = runAsync (buildPlan cfg packagePath) in
    Term.(ret (const cmd $ configTerm $ pkgPathTerm)),
    Term.info "build-plan" ~version ~doc ~sdocs ~exits
  in

  let buildShellCommand =
    let doc = "Enter the build shell" in
    let cmd cfg packagePath = runAsync (buildShell cfg packagePath) in
    Term.(ret (const cmd $ configTerm $ pkgPathTerm)),
    Term.info "build-shell" ~version ~doc ~sdocs ~exits
  in

  let buildPackageCommand =
    let doc = "Build specified package" in
    let cmd cfg packagePath = runAsync (buildPackage cfg packagePath) in
    Term.(ret (const cmd $ configTerm $ pkgPathTerm)),
    Term.info "build-package" ~version ~doc ~sdocs ~exits
  in

  let buildCommand =
    let doc = "Build entire sandbox" in
    let cmd cfg command = runAsync (build cfg command) in
    let commandTerm =
      Arg.(non_empty & (pos_all string []) & (info [] ~docv:"COMMAND"))
    in
    Term.(ret (const cmd $ configTerm $ commandTerm)),
    Term.info "build" ~version ~doc ~sdocs ~exits
  in

  let commands = [
    buildEnvCommand;
    buildPlanCommand;
    buildShellCommand;
    buildPackageCommand;
    buildCommand;
  ] in Term.(exit @@ eval_choice defaultCommand commands);
