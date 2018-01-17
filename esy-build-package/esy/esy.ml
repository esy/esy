module Path = EsyCore.Path
module Package = EsyCore.Package
module BuildTask = EsyCore.BuildTask
module Environment = EsyCore.Environment
module Sandbox = EsyCore.Sandbox
module Run = EsyCore.Run
module RunAsync = EsyCore.RunAsync

let cwd = Sys.getcwd ()

let path =
  let open Cmdliner in
  let parse = Path.of_string in
  let print = Path.pp in
  Arg.conv ~docv:"PATH" (parse, print)

let resolvedPath =
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

let packagePath =
  let open Cmdliner in
  let doc = "Path to package." in
  Arg.(
    value
    & pos 0  (some resolvedPath) None
    & info [] ~doc
  )

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

let buildEnv (opts : CommonOpts.t) (packagePath : Path.t option) =
  let open RunAsync.Syntax in

  let printBuildEnv (pkg : Package.t) =
    let%bind _task, buildEnv = RunAsync.liftOfRun (BuildTask.ofPackage pkg) in
    let header = Printf.sprintf "# Build environment for %s@%s" pkg.name pkg.version in
    let%bind source = RunAsync.liftOfRun (
      Environment.renderToShellSource
        ~header
        (* FIXME: those paths are invalid *)
        ~sandboxPath:opts.sandboxPath
        ~storePath:opts.sandboxPath
        ~localStorePath:opts.sandboxPath
        buildEnv
    ) in
    let%lwt () = Lwt_io.print source in
    return ()
  in

  let%bind pkg = Sandbox.ofDir opts.sandboxPath in

  match packagePath with
  | Some packagePath ->
    let findByPath (pkg : Package.t) =
      Path.equal pkg.sourcePath packagePath
    in begin match Package.DependencyGraph.find ~f:findByPath pkg with
    | None ->
      let msg = Printf.sprintf "No package found at %s" (Path.to_string packagePath) in
      error msg
    | Some pkg -> printBuildEnv pkg
    end
  | None -> printBuildEnv pkg

let buildPlan (opts : CommonOpts.t) =
  let open RunAsync.Syntax in
  let%bind sandbox = Sandbox.ofDir opts.sandboxPath in
  let%bind task, _buildEnv = RunAsync.liftOfRun (BuildTask.ofPackage sandbox) in
  return (
    task
    |> BuildTask.ExternalFormat.ofBuildTask
    |> BuildTask.ExternalFormat.to_yojson
    |> Yojson.Safe.pretty_print Format.std_formatter)

let build (opts : CommonOpts.t) =
  let open RunAsync.Syntax in
  let%bind sandbox = Sandbox.ofDir opts.sandboxPath in
  let%bind _task, _buildEnv = RunAsync.liftOfRun (BuildTask.ofPackage sandbox) in
  return ()

let run (cmd : unit Run.t) =
  match cmd with
  | Ok () -> `Ok ()
  | Error error ->
    let msg = Run.formatError error in
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
    Term.(ret (const cmd $ CommonOpts.term)),
    Term.info "esy" ~version ~doc ~sdocs ~exits
  in

  let buildEnvCommand =
    let doc = "Print build environment to stdout" in
    let cmd opts packagePath = runAsync (buildEnv opts packagePath) in
    Term.(ret (const cmd $ CommonOpts.term $ packagePath)),
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
