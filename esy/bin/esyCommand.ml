open Esy

let done_ msg =
  let line = Chalk.green("[INFO]") ^ " " ^ msg in
  print_endline line

let info msg =
  let line = Chalk.blue("[INFO]") ^ " " ^ msg in
  print_endline line

let warn msg =
  let line = Chalk.yellow("[WARN]") ^ " " ^ msg in
  print_endline line

let error msg =
  let line = Chalk.red("[ERR]") ^ " " ^ msg in
  print_endline line

(**
 * This module encapsulates info about esy runtime - its version, current
 * working directory and so on.
 *
 * XXX: Probably needs to be merged with Config
 *)
module EsyRuntime = struct

  let currentWorkingDir = Path.v (Sys.getcwd ())
  let currentExecutable = Path.v Sys.executable_name

  let resolve req =
    let open RunAsync.Syntax in
    let%bind currentFilename = Fs.realpath currentExecutable in
    let currentDirname = Path.parent currentFilename in
    let%bind cmd =
      match EsyBuildPackage.NodeResolution.resolve req currentDirname with
      | Ok (Some path) -> return path
      | Ok (None) ->
        let msg =
          Printf.sprintf
          "unable to resolve %s from %s"
          req
          (Path.to_string currentDirname)
        in
        RunAsync.error msg
      | Error (`Msg err) -> RunAsync.error err
    in return cmd

  let resolveCommand req =
    let open RunAsync.Syntax in
    let%bind path = resolve req in
    return (path |> Cmd.p |> Cmd.v)

  let esyInstallJsCommand =
    resolveCommand "../../../../bin/esy-install.js"

  let fastreplacestringCommand =
    resolveCommand "fastreplacestring/.bin/fastreplacestring.exe"

  let esyBuildPackageCommand =
    resolveCommand "../../esy-build-package/bin/esyBuildPackageCommand.exe"

  let esyICommand =
    resolveCommand "../../esyi/bin/esyi.exe"

  let esyInstallRelease =
    resolve "../../../../bin/esyInstallRelease.js"

  module EsyPackageJson = struct
    type t = {
      version : string
    } [@@deriving of_yojson { strict = false }]

    let read () =
      let pkgJson =
        let open RunAsync.Syntax in
        let%bind filename = resolve "../../../../package.json" in
        let%bind data = Fs.readFile filename in
        Lwt.return (Json.parseStringWith of_yojson data)
      in Lwt_main.run pkgJson
  end

  (** This is set by bash script wrapper currently *)
  let version =
    match EsyPackageJson.read () with
    | Ok pkgJson -> pkgJson.EsyPackageJson.version
    | Error err ->
      let msg =
        let err = Run.formatError err in
        Printf.sprintf "invalid esy installation: cannot read package.json %s" err in
      failwith msg

  let concurrency =
    (** TODO: handle more platforms, right now this is tested only on macOS and
    * Linux *)
    let cmd = Bos.Cmd.(v "getconf" % "_NPROCESSORS_ONLN") in
    match Bos.OS.Cmd.(run_out cmd |> to_string) with
    | Ok out -> begin match out |> String.trim |> int_of_string_opt with
        | Some n -> n
        | None -> 1
      end
    | Error _ -> 1
end

let esyEnvOverride (cfg : Config.t) =
  let env = Astring.String.Map.(
      empty
      |> add "ESY__PREFIX" (Path.to_string cfg.prefixPath)
      |> add "ESY__SANDBOX" (Path.to_string cfg.sandboxPath)
    ) in
  `CurrentEnvOverride env

let resolvedPathTerm =
  let open Cmdliner in
  let parse v =
    match Path.of_string v with
    | Ok path ->
      if Path.is_abs path then
        Ok path
      else
        Ok Path.(EsyRuntime.currentWorkingDir // path |> normalize)
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
      & opt (some Cli.pathConv) None
      & info ["prefix-path"; "P"] ~env ~docs ~doc
    )
  in
  let sandboxPath =
    let doc = "Specifies esy sandbox path." in
    let env = Arg.env_var "ESY__SANDBOX" ~doc in
    Arg.(
      value
      & opt (some Cli.pathConv) None
      & info ["sandbox-path"; "S"] ~env ~docs ~doc
    )
  in

  let resolveSandoxPath () =
    let open RunAsync.Syntax in

    let isSandoxPath path =
      if%bind Fs.exists Path.(path / "package.json")
      then return true
      else if%bind Fs.exists Path.(path / "esy.json")
      then return true
      else return false
    in

    let%bind currentPath = RunAsync.ofRun (Path.current ()) in

    let rec climb path =
      if%bind isSandoxPath path
      then return path
      else
        let parent = Path.parent path in
        if not (Path.equal path parent)
        then climb (Path.parent path)
        else
          let%bind msg = RunAsync.ofRun (
            let open Run.Syntax in
            let%bind currentPath = Path.toPrettyString currentPath in
            let msg = Printf.sprintf "No sandbox found (from %s and up)" currentPath in
            return msg
          ) in error msg
    in

    climb currentPath
  in

  let parse prefixPath sandboxPath =
    let open RunAsync.Syntax in
    let%bind sandboxPath =
      match sandboxPath with
      | Some v -> return v
      | None -> resolveSandoxPath ()
    in
    let%bind prefixPath = match prefixPath with
      | Some prefixPath -> return (Some prefixPath)
      | None ->
        let%bind rc = EsyRc.ofPath sandboxPath in
        return rc.EsyRc.prefixPath
    in
    let%bind esyBuildPackageCommand = EsyRuntime.esyBuildPackageCommand in
    let%bind fastreplacestringCommand = EsyRuntime.fastreplacestringCommand in
    let%bind esyInstallJsCommand = EsyRuntime.esyInstallJsCommand in
    Config.create
      ~esyInstallJsCommand
      ~esyBuildPackageCommand
      ~fastreplacestringCommand
      ~esyVersion:EsyRuntime.version ~prefixPath sandboxPath
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
  Term.(
    const setupLog
    $ Fmt_cli.style_renderer ()
    $ Logs_cli.level ~env:(Arg.env_var "ESY__LOG") ())

let runCommandViaNode cfg name args =
  let open RunAsync.Syntax in
  let%bind cfg = cfg in
  let env = esyEnvOverride cfg in
  match%lwt EsyRuntime.esyInstallJsCommand with
  | Ok esyJs ->
    let cmd = Cmd.(v "node" %% esyJs % name %% Cmd.ofList args) in
    ChildProcess.run ~env cmd
  | Error _err ->
    RunAsync.error "unable to find esy-install.js"

let withBuildTaskByPath
    ~(info : SandboxInfo.t)
    packagePath
    f =
  let open RunAsync.Syntax in
  match packagePath with
  | Some packagePath ->
    let resolvedPath = packagePath |> Path.rem_empty_seg |> Path.to_string in
    let findByPath (task : Task.t) =
      String.equal resolvedPath task.pkg.id
    in begin match Task.DependencyGraph.find ~f:findByPath info.task with
      | None ->
        let msg = Printf.sprintf "No package found at %s" resolvedPath in
        error msg
      | Some pkg -> f pkg
    end
  | None -> f info.task

let buildPlan cfg packagePath =
  let open RunAsync.Syntax in

  let%bind cfg = cfg in
  let%bind info = SandboxInfo.ofConfig cfg in

  let f task =
    return (
      Task.toBuildProtocolString ~pretty:true task
      |> print_endline
    )
  in withBuildTaskByPath ~info packagePath f

let buildShell cfg packagePath =
  let open RunAsync.Syntax in

  let%bind cfg = cfg in
  let%bind info = SandboxInfo.ofConfig cfg in

  let f task =
    let%bind () = Build.buildDependencies ~concurrency:EsyRuntime.concurrency cfg task in
    match%bind PackageBuilder.buildShell cfg task with
    | Unix.WEXITED 0 -> return ()
    | Unix.WEXITED n
    | Unix.WSTOPPED n
    | Unix.WSIGNALED n -> exit n
  in withBuildTaskByPath ~info packagePath f

let buildPackage cfg packagePath =
  let open RunAsync.Syntax in

  let%bind cfg = cfg in
  let%bind info = SandboxInfo.ofConfig cfg in

  let f task =
    Build.buildAll ~concurrency:EsyRuntime.concurrency ~force:`ForRoot cfg task
  in withBuildTaskByPath ~info packagePath f

let build ?(buildOnly=true) cfg command =
  let open RunAsync.Syntax in
  let%bind cfg = cfg in
  let%bind {SandboxInfo. task; _} = SandboxInfo.ofConfig cfg in

  (** TODO: figure out API to build devDeps in parallel with the root *)

  match command with
  | [] ->
    let%bind () =
      Build.buildDependencies
        ~concurrency:EsyRuntime.concurrency
        ~force:`ForRoot
        cfg task
    in Build.buildTask ~force:true ~stderrout:`Keep ~quiet:true ~buildOnly cfg task

  | command ->
    let%bind () = Build.buildDependencies ~concurrency:EsyRuntime.concurrency cfg task in
    match%bind PackageBuilder.buildExec cfg task command with
    | Unix.WEXITED 0 -> return ()
    | Unix.WEXITED n
    | Unix.WSTOPPED n
    | Unix.WSIGNALED n -> exit n

let makeEnvCommand ~computeEnv ~header cfg asJson packagePath =
  let open RunAsync.Syntax in

  let%bind cfg = cfg in
  let%bind info = SandboxInfo.ofConfig cfg in

  let f (task : Task.t) =
    let%bind source = RunAsync.ofRun (
        let open Run.Syntax in
        let%bind env = computeEnv task.pkg in
        let header = header task.pkg in
        if asJson
        then
          let%bind env = Environment.Value.ofBindings env in
          let%bind env = Environment.Value.bindToConfig cfg env in
          Ok (
            env
            |> Environment.Value.to_yojson
            |> Yojson.Safe.pretty_to_string)
        else
          Environment.renderToShellSource
            ~header
            ~sandboxPath:cfg.sandboxPath
            ~storePath:cfg.storePath
            ~localStorePath:cfg.localStorePath
            env
      ) in
    let%lwt () = Lwt_io.print source in
    return ()
  in withBuildTaskByPath ~info packagePath f

let buildEnv =
  let header (pkg : Package.t) =
    Printf.sprintf "# Build environment for %s@%s" pkg.name pkg.version
  in
  makeEnvCommand ~computeEnv:Task.buildEnv ~header

let commandEnv =
  let open Run.Syntax in
  let header (pkg : Package.t) =
    Printf.sprintf "# Command environment for %s@%s" pkg.name pkg.version
  in
  let computeEnv pkg =
    let%bind env = Task.commandEnv pkg in
    Ok (Environment.current @ env)
  in
  makeEnvCommand ~computeEnv ~header

let sandboxEnv =
  let open Run.Syntax in
  let header (pkg : Package.t) =
    Printf.sprintf "# Sandbox environment for %s@%s" pkg.name pkg.version
  in
  let computeEnv pkg =
    let%bind env = Task.sandboxEnv pkg in
    Ok (Environment.current @ env)
  in
  makeEnvCommand ~computeEnv ~header

let makeExecCommand
    ?(checkIfDependenciesAreBuilt=false)
    ?prepare
    ~env
    cfg
    command
  =
  let open RunAsync.Syntax in

  let%bind cfg = cfg in
  let%bind (info: SandboxInfo.t) = SandboxInfo.ofConfig cfg in

  let%bind () = match prepare with
    | None -> return ()
    | Some prepare -> prepare cfg info.task
  in

  let%bind () =
    if checkIfDependenciesAreBuilt
    then Build.buildDependencies ~concurrency:EsyRuntime.concurrency cfg info.task
    else return ()
  in

  let%bind env = RunAsync.ofRun (
      let open Run.Syntax in
      let env = match env with
        | `CommandEnv -> info.commandEnv
        | `SandboxEnv -> info.sandboxEnv
      in
      let env = Environment.current @ env in
      let%bind env = Environment.Value.ofBindings env in
      let%bind env = Environment.Value.bindToConfig cfg env in
      Ok (`CustomEnv env)
    ) in

  let%bind status = ChildProcess.runToStatus
    ~env
    ~resolveProgramInEnv:true
    ~stderr:(`FD_copy Unix.stderr)
    ~stdout:(`FD_copy Unix.stdout)
    ~stdin:(`FD_copy Unix.stdin)
    (Cmd.ofList command)
  in match status with
  | Unix.WEXITED n
  | Unix.WSTOPPED n
  | Unix.WSIGNALED n -> exit n

let exec cfgRes =
  let open RunAsync.Syntax in
  let prepare cfg (task : Task.t) =
    let installPath = Config.ConfigPath.toPath cfg task.paths.installPath in
    if%bind Fs.exists installPath then
      return ()
    else
      build ~buildOnly:false cfgRes []
  in
  makeExecCommand
    ~prepare
    ~env:`SandboxEnv
    cfgRes

let devExec =
  makeExecCommand
    ~checkIfDependenciesAreBuilt:true
    ~env:`CommandEnv

let devShell cfg =
  let shell =
    try Sys.getenv "SHELL"
    with Not_found -> "/bin/bash"
  in
  makeExecCommand
    ~env:`CommandEnv
    cfg
    [shell]

let makeLsCommand ~computeTermNode ~includeTransitive cfg (info: SandboxInfo.t) =
  let open RunAsync.Syntax in

  let seen = ref StringSet.empty in

  let f ~foldDependencies _prev (task : Task.t) =
    if StringSet.mem task.id !seen then
      return None
    else (
      seen := StringSet.add task.id !seen;
      let%bind children =
        if not includeTransitive && task.id <> info.task.id then
          return []
        else
          foldDependencies ()
          |> List.map (fun (_, v) -> v)
          |> RunAsync.List.joinAll
      in
      let children = children |> Std.List.filterNone in
      computeTermNode ~cfg task children
    )
  in

  match%bind Task.DependencyGraph.fold ~f ~init:(return None) info.task with
  | Some tree -> return (print_endline (Esy.TermTree.toString tree))
  | None -> return ()

let lsBuilds ~includeTransitive cfg =
  let open RunAsync.Syntax in

  let%bind cfg = cfg in
  let%bind (info : SandboxInfo.t) = SandboxInfo.ofConfig cfg in

  let computeTermNode ~cfg task children =
    let%bind built = Task.isBuilt ~cfg task in
    let%bind line = SandboxTools.formatPackageInfo ~built task in
    return (Some (TermTree.Node { line; children; }))
  in
  makeLsCommand ~computeTermNode ~includeTransitive cfg info

let lsLibs ~includeTransitive cfg =
  let open RunAsync.Syntax in

  let%bind cfg = cfg in
  let%bind (info : SandboxInfo.t) = SandboxInfo.ofConfig cfg in

  let%bind ocamlfind = SandboxTools.getOcamlfind ~cfg info.task in
  let%bind builtIns = SandboxTools.getPackageLibraries ~cfg ~ocamlfind () in

  let computeTermNode ~cfg (task: Task.t) children =
    let%bind built = Task.isBuilt ~cfg task in
    let%bind line = SandboxTools.formatPackageInfo ~built task in

    let%bind libs =
      if built then
        SandboxTools.getPackageLibraries ~cfg ~ocamlfind ~builtIns ~task ()
      else
        return []
    in

    let libs =
      libs
      |> List.map (fun lib ->
          let line = Chalk.yellow(lib) in
          TermTree.Node { line; children = []; }
        )
    in

    return (Some (TermTree.Node { line; children = libs @ children; }))
  in
  makeLsCommand ~computeTermNode ~includeTransitive cfg info

let lsModules ~libs:only cfg =
  let open RunAsync.Syntax in

  let%bind cfg = cfg in
  let%bind (info : SandboxInfo.t) = SandboxInfo.ofConfig cfg in

  let%bind ocamlfind = SandboxTools.getOcamlfind ~cfg info.task in
  let%bind ocamlobjinfo = SandboxTools.getOcamlobjinfo ~cfg info.task in
  let%bind builtIns = SandboxTools.getPackageLibraries ~cfg ~ocamlfind () in

  let formatLibraryModules ~cfg ~task lib =
    let%bind meta = SandboxTools.queryMeta ~cfg ~ocamlfind ~task lib in
    let open SandboxTools in

    if String.length(meta.archive) == 0 then
      let description = Chalk.dim(meta.description) in
      return [TermTree.Node { line=description; children=[]; }]
    else begin
      Path.of_string (meta.location ^ Path.dir_sep ^ meta.archive) |> function
      | Ok archive ->
        if%bind Fs.exists archive then begin
          let archive = Path.to_string archive in
          let%bind lines =
            SandboxTools.queryModules ~ocamlobjinfo archive
          in

          let modules =
            lines |> List.map(fun line ->
                let line = Chalk.cyan(line) in
                TermTree.Node { line; children=[]; }
              )
          in

          return modules
        end else
          return []
      | Error `Msg msg -> error msg
    end
  in

  let computeTermNode ~cfg (task: Task.t) children =
    let%bind built = Task.isBuilt ~cfg task in
    let%bind line = SandboxTools.formatPackageInfo ~built task in

    let%bind libs =
      if built then
        SandboxTools.getPackageLibraries ~cfg ~ocamlfind ~builtIns ~task ()
      else
        return []
    in

    let isNotRoot = task.id <> info.task.id in
    let constraintsSet = List.length only <> 0 in
    let noMatchedLibs = List.length (Std.List.intersect only libs) = 0 in

    if isNotRoot && constraintsSet && noMatchedLibs then
      return None
    else
      let%bind libs =
        libs
        |> List.filter (fun lib ->
            if List.length only = 0 then
              true
            else
              List.mem lib only
          )
        |> List.map (fun lib ->
            let line = Chalk.yellow(lib) in
            let%bind children =
              formatLibraryModules ~cfg ~task lib
            in
            return (TermTree.Node { line; children; })
          )
        |> RunAsync.List.joinAll
      in

      return (Some (TermTree.Node { line; children = libs @ children; }))
  in
  makeLsCommand ~computeTermNode ~includeTransitive:false cfg info

let () =
  let open Cmdliner in

  (** Prelude *)

  let exits = Term.default_exits in
  let sdocs = Manpage.s_common_options in
  (** CLI helpers *)

  let runCommand (cmd : unit Run.t) =
    match cmd with
    | Ok () -> `Ok ()
    | Error error ->
      let msg = Run.formatError error in
      let msg = Printf.sprintf "error, exiting...\n%s" msg in
      `Error (false, msg)
  in

  let runAsyncCommand ?(header=`Standard) ~info cmd =
    let work () =
      let%lwt () = match header with
        | `Standard -> begin match Cmdliner.Term.name info with
            | "esy" -> Logs_lwt.app (fun m -> m "esy %s" EsyRuntime.version)
            | name -> Logs_lwt.app (fun m -> m "esy %s %s" name EsyRuntime.version);
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
    let info = Term.info "esy" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg command () =
      runAsyncCommand ~header:`No ~info (devExec cfg command)
    in
    let commandTerm =
      Arg.(non_empty & (pos_all string []) & (info [] ~docv:"COMMAND"))
    in
    Term.(ret (const cmd $ configTerm $ commandTerm $ setupLogTerm)), info
  in

  let buildPlanCommand =
    let doc = "Print build plan to stdout" in
    let info = Term.info "build-plan" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg packagePath () =
      runAsyncCommand ~header:`No ~info (buildPlan cfg packagePath)
    in
    Term.(ret (const cmd $ configTerm $ pkgPathTerm $ setupLogTerm)), info
  in

  let buildShellCommand =
    let doc = "Enter the build shell" in
    let info = Term.info "build-shell" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg packagePath () =
      runAsyncCommand ~info (buildShell cfg packagePath)
    in
    Term.(ret (const cmd $ configTerm $ pkgPathTerm $ setupLogTerm)), info
  in

  let buildPackageCommand =
    let doc = "Build specified package" in
    let info = Term.info "build-package" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg packagePath () =
      runAsyncCommand ~info (buildPackage cfg packagePath)
    in
    Term.(ret (const cmd $ configTerm $ pkgPathTerm $ setupLogTerm)), info
  in

  let installNextCommand =
    let doc = "Install dependendencies using esyi (experimental)" in
    let info =
      Term.info "install-next"
        ~version:EsyRuntime.version
        ~doc
        ~sdocs
        ~exits
    in

    let installNext cfg =
      let open RunAsync.Syntax in

      let%bind cfg = cfg in

      match%lwt EsyRuntime.esyICommand with
      | Ok commandPath ->
        let cmd = Cmd.(commandPath % p cfg.Config.sandboxPath) in
        ChildProcess.run cmd
      | Error _err ->
        RunAsync.error "unable to find esyi"
    in

    let cmd cfg () =
      runAsyncCommand ~info (installNext cfg)
    in
    Term.(ret (const cmd $ configTerm $ setupLogTerm)), info
  in

  let buildCommand =
    let doc = "Build entire sandbox" in
    let info = Term.info "build" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg command () =
      let header = match command with
        | [] -> `Standard
        | _ -> `No
      in
      runAsyncCommand ~header ~info (build cfg command)
    in
    let commandTerm =
      Arg.(value & (pos_all string []) & (info [] ~docv:"COMMAND"))
    in
    Term.(ret (const cmd $ configTerm $ commandTerm $ setupLogTerm)), info
  in

  let buildEnvCommand =
    let doc = "Print build environment to stdout" in
    let info = Term.info "build-env" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg asJson packagePath () =
      runAsyncCommand ~header:`No ~info (buildEnv cfg asJson packagePath)
    in
    let json =
      let doc = "Format output as JSON" in
      Arg.(value & flag & info ["json"]  ~doc);
    in
    Term.(ret (const cmd $ configTerm $ json $ pkgPathTerm $ setupLogTerm)), info
  in

  let commandEnvCommand =
    let doc = "Print command environment to stdout" in
    let info = Term.info "command-env" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg asJson packagePath () =
      runAsyncCommand ~header:`No ~info (commandEnv cfg asJson packagePath)
    in
    let json =
      let doc = "Format output as JSON" in
      Arg.(value & flag & info ["json"]  ~doc);
    in
    Term.(ret (const cmd $ configTerm $ json $ pkgPathTerm $ setupLogTerm)), info
  in

  let sandboxEnvCommand =
    let doc = "Print install environment to stdout" in
    let info = Term.info "sandbox-env" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg asJson packagePath () =
      runAsyncCommand ~header:`No ~info (sandboxEnv cfg asJson packagePath)
    in
    let json =
      let doc = "Format output as JSON" in
      Arg.(value & flag & info ["json"]  ~doc);
    in
    Term.(ret (const cmd $ configTerm $ json $ pkgPathTerm $ setupLogTerm)), info
  in

  let execCommand =
    let doc = "Execute command as if the package is installed" in
    let info = Term.info "x" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg command () =
      runAsyncCommand ~header:`No ~info (exec cfg command)
    in
    let commandTerm =
      Arg.(non_empty & (pos_all string []) & (info [] ~docv:"COMMAND"))
    in
    Term.(ret (const cmd $ configTerm $ commandTerm $ setupLogTerm)), info
  in

  let shellCommand =
    let doc = "Enter esy sandbox shell" in
    let info = Term.info "shell" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg () =
      runAsyncCommand ~header:`No ~info (devShell cfg)
    in
    Term.(ret (const cmd $ configTerm $ setupLogTerm)), info
  in

  let lsBuildsCommand =
    let doc = "Output a tree of packages in the sandbox along with their status" in
    let info = Term.info "ls-builds" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd includeTransitive cfg () =
      runAsyncCommand ~info (lsBuilds ~includeTransitive cfg)
    in
    let includeTransitive =
      let doc = "Include transitive dependencies" in
      Arg.(value & flag & info ["T"; "include-transitive"]  ~doc);
    in
    Term.(ret (const cmd $ includeTransitive $ configTerm $ setupLogTerm)), info
  in

  let lsLibsCommand =
    let doc = "Output a tree of packages along with the set of libraries made available by each package dependency." in
    let info = Term.info "ls-libs" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd includeTransitive cfg () =
      runAsyncCommand ~info (lsLibs ~includeTransitive cfg)
    in
    let includeTransitive =
      let doc = "Include transitive dependencies" in
      Arg.(value & flag & info ["T"; "include-transitive"]  ~doc);
    in
    Term.(ret (const cmd $ includeTransitive $ configTerm $ setupLogTerm)), info
  in

  let lsModulesCommand =
    let doc = "Output a tree of packages along with the set of libraries and modules made available by each package dependency." in
    let info = Term.info "ls-modules" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd libs cfg () =
      runAsyncCommand ~info (lsModules ~libs cfg)
    in
    let lib =
      let doc = "Output modules only for specified lib(s)" in
      Arg.(value & (pos_all string []) & info [] ~docv:"LIB" ~doc);
    in
    Term.(ret (const cmd $ lib $ configTerm $ setupLogTerm)), info
  in

  let dependenciesForExport (task : Task.t) =
    let f deps dep = match dep with
      | Task.Dependency ({
          sourceType = Package.SourceType.Immutable;
          _
        } as task)
      | Task.BuildTimeDependency ({
          sourceType = Package.SourceType.Immutable; _
        } as task) ->
        (task, dep)::deps
      | Task.Dependency _
      | Task.DevDependency _
      | Task.BuildTimeDependency _ -> deps
    in
    task.dependencies
    |> ListLabels.fold_left ~f ~init:[]
    |> ListLabels.rev
  in

  let exportBuildCommand =
    let doc = "Export build from the store" in
    let info = Term.info "export-build" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg (buildPath : Path.t) () =
      let open RunAsync.Syntax in
      let f =
        let%bind cfg = cfg in
        let outputPrefixPath = Path.(EsyRuntime.currentWorkingDir / "_export") in
        Task.exportBuild ~outputPrefixPath ~cfg buildPath
      in
      runAsyncCommand ~info f
    in
    let buildPathTerm =
      let doc = "Path with builds." in
      Arg.(
        required
        & pos 0  (some resolvedPathTerm) None
        & info [] ~doc
      )
    in
    Term.(ret (const cmd $ configTerm $ buildPathTerm $ setupLogTerm)), info
  in

  let exportDependenciesCommand =
    let doc = "Export sandbox dependendencies as prebuilt artifacts" in
    let info = Term.info "export-dependencies" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg () =
      let f =
        let open RunAsync.Syntax in

        let%bind cfg = cfg in
        let%bind {SandboxInfo. task = rootTask; _} = SandboxInfo.ofConfig cfg in

        let tasks =
          rootTask
          |> Task.DependencyGraph.traverse ~traverse:dependenciesForExport
          |> List.filter (fun (task : Task.t) -> not (task.id = rootTask.id))
        in

        let queue = LwtTaskQueue.create ~concurrency:8 () in

        let exportBuild (task : Task.t) =
          let aux () =
            let%lwt () = Logs_lwt.app (fun m -> m "Exporting %s@%s" task.pkg.name task.pkg.version) in
            let buildPath = Config.ConfigPath.toPath cfg task.paths.installPath in
            if%bind Fs.exists buildPath
            then
              let outputPrefixPath = Path.(EsyRuntime.currentWorkingDir / "_export") in
              Task.exportBuild ~outputPrefixPath ~cfg buildPath
            else (
              let msg =
                Printf.sprintf
                  "%s@%s was not built, run 'esy build' first"
                  task.pkg.name
                  task.pkg.version
              in error msg
            )
          in LwtTaskQueue.submit queue aux
        in

        tasks
        |> List.map exportBuild
        |> RunAsync.List.waitAll
      in
      runAsyncCommand ~info f
    in
    Term.(ret (const cmd $ configTerm $ setupLogTerm)), info
  in

  let importBuildCommand =
    let doc = "Import build into the store" in
    let info = Term.info "import-build" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg fromPath (buildPaths : Path.t list) () =
      let f =
        let open RunAsync.Syntax in
        let%bind cfg = cfg in
        let%bind buildPaths = match fromPath with
        | Some fromPath ->
          let%bind lines = Fs.readFile fromPath in
          return (
            buildPaths @ (
            lines
            |> String.split_on_char '\n'
            |> List.filter (fun line -> String.trim line <> "")
            |> List.map (fun line -> Path.v line))
          )
        | None -> return buildPaths
        in
        let queue = LwtTaskQueue.create ~concurrency:8 () in
        buildPaths
        |> List.map (fun path -> LwtTaskQueue.submit queue (fun () -> Task.importBuild cfg path))
        |> RunAsync.List.waitAll
      in
      runAsyncCommand ~info f
    in
    let buildPathsTerm =
      Arg.(value & (pos_all resolvedPathTerm []) & (info [] ~docv:"BUILD"))
    in
    let fromTerm =
      Arg.(
        value
        & opt (some resolvedPathTerm) None
        & info ["from"; "f"] ~docv:"FROM"
      )
    in
    Term.(ret (const cmd $ configTerm $ fromTerm $ buildPathsTerm $ setupLogTerm)), info
  in

  let importDependenciesCommand =
    let doc = "Import sandbox dependencies" in
    let info = Term.info "import-dependencies" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg fromPath () =
      let f =
        let open RunAsync.Syntax in

        let%bind cfg = cfg in
        let%bind {SandboxInfo. task = rootTask; _} = SandboxInfo.ofConfig cfg in

        let fromPath = match fromPath with
          | Some fromPath -> fromPath
          | None -> Path.(cfg.Config.sandboxPath / "_export")
        in

        let pkgs =
          rootTask
          |> Task.DependencyGraph.traverse ~traverse:dependenciesForExport
          |> List.filter (fun (task : Task.t) -> not (task.Task.id = rootTask.id))
        in

        let queue = LwtTaskQueue.create ~concurrency:16 () in

        let importBuild (task : Task.t) =
          let aux () =
            let installPath = Config.ConfigPath.toPath cfg task.paths.installPath in
            if%bind Fs.exists installPath
            then return ()
            else (
              let pathDir = Path.(fromPath / task.id) in
              let pathTgz = Path.(fromPath / (task.id ^ ".tar.gz")) in
              if%bind Fs.exists pathDir
              then Task.importBuild cfg pathDir
              else if%bind Fs.exists pathTgz
              then Task.importBuild cfg pathTgz
              else
                let%lwt () =
                  Logs_lwt.warn(fun m -> m "no prebuilt artifact found for %s" task.id)
                in return ()
            )
          in LwtTaskQueue.submit queue aux
        in

        pkgs
        |> List.map importBuild
        |> RunAsync.List.waitAll
      in
      runAsyncCommand ~info f
    in
    let fromPathTerm =
      let open Cmdliner in
      let doc = "Path with builds." in
      Arg.(
        value
        & pos 0  (some resolvedPathTerm) None
        & info [] ~doc
      )
    in
    Term.(ret (const cmd $ configTerm $ fromPathTerm $ setupLogTerm)), info
  in

  let releaseCommand =
    let doc = "Produce npm package with prebuilt artifacts" in
    let info = Term.info "release" ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd cfg () =
      runAsyncCommand ~info (
        let open RunAsync.Syntax in
        let%bind cfg = cfg in
        let%bind {SandboxInfo. sandbox; _} = SandboxInfo.ofConfig cfg in

        let%bind outputPath =
          let outputDir = "_release" in
          let outputPath = Path.(cfg.Config.sandboxPath / outputDir) in
          let%bind () = Fs.rmPath outputPath in
          return outputPath
        in

        let%bind esyInstallRelease = EsyRuntime.esyInstallRelease in

        NpmRelease.make
          ~esyInstallRelease
          ~outputPath
          ~concurrency:EsyRuntime.concurrency
          ~cfg
          ~sandbox
      )
    in
    Term.(ret (const cmd $ configTerm $ setupLogTerm)), info
  in

  let helpCommand =
    let info = Term.info "help" ~version:EsyRuntime.version ~doc:"Show this message and exit" ~sdocs ~exits in
    let cmd () =
      `Help (`Auto, None)
    in
    Term.(ret (const cmd $ const ())), info
  in

  let versionCommand =
    let info = Term.info "version" ~version:EsyRuntime.version ~doc:"Print esy version and exit" ~sdocs ~exits in
    let cmd () =
      print_endline EsyRuntime.version;
      `Ok ()
    in
    Term.(ret (const cmd $ const ())), info
  in

  let makeCommandDelegatingToJsImpl ~name ~doc =
    let info = Term.info name ~version:EsyRuntime.version ~doc ~sdocs ~exits in
    let cmd args cfg () =
      let f = runCommandViaNode cfg name args in
      runAsyncCommand ~info f
    in
    let argTerm =
      Arg.(value & (pos_all string []) & (info [] ~docv:"COMMAND"))
    in
    Term.(ret (const cmd $ argTerm $ configTerm $ setupLogTerm)), info
  in

  let installCommand =
    makeCommandDelegatingToJsImpl
      ~name:"install"
      ~doc:"Install dependencies"
  in

  let makeAlias command alias =
    let term, info = command in
    let name = Term.name info in
    let doc = Printf.sprintf "An alias for $(b,%s) command" name in
    term, Term.info alias ~version:EsyRuntime.version ~doc ~sdocs ~exits
  in

  let commands = [
    (* commands *)
    buildPlanCommand;
    buildShellCommand;
    buildPackageCommand;
    buildCommand;

    shellCommand;

    buildEnvCommand;
    commandEnvCommand;
    sandboxEnvCommand;

    lsBuildsCommand;
    lsLibsCommand;
    lsModulesCommand;

    exportDependenciesCommand;
    importDependenciesCommand;

    execCommand;

    helpCommand;
    versionCommand;

    exportBuildCommand;
    importBuildCommand;

    releaseCommand;

    installNextCommand;

    (* commands implemented via JS *)
    installCommand;
    makeCommandDelegatingToJsImpl
      ~name:"add"
      ~doc:"Add new dependency";
    makeCommandDelegatingToJsImpl
      ~name:"install-cache"
      ~doc:"Manage installation cache";
    makeCommandDelegatingToJsImpl
      ~name:"init"
      ~doc:"Initialize new project";
    makeCommandDelegatingToJsImpl
      ~name:"import-opam"
      ~doc:"Produce esy package metadata from OPAM package metadata";

    (* aliases *)
    makeAlias buildCommand "b";
    makeAlias installCommand "i";
  ] in

  let hasCommand name =
    List.exists
      (fun (_cmd, info) -> Term.name info = name)
      commands
  in

  let runCmdliner argv =
    Term.(exit @@ eval_choice ~argv defaultCommand commands);
  in

  let commandName =
    let open Option.Syntax in
    let%bind commandName =
      try Some Sys.argv.(1)
      with Invalid_argument _ -> None
    in
    if String.get commandName 0 = '-'
    then None
    else Some commandName
  in

  match commandName with

  (*
   * Fixup invocations for commands which pass their arguments through to other
   * executables.
   *
   * TODO: currently this is implemented in a way which prevents common options
   * (like --sandbox-path or --prefix-path) from working for these commands.
   * This should be fixed.
   *)
  | Some "init"
  | Some "import-opam"
  | Some "install"
  | Some "add"
  | Some "install-cache"
  | Some "x"
  | Some "b"
  | Some "build" ->
    let argv =
      match Array.to_list Sys.argv with
      | prg::command::rest -> prg::command::"--"::rest
      | argv -> argv
    in
    let argv = Array.of_list argv in
    runCmdliner argv

  | Some "" ->
    runCmdliner Sys.argv

  (*
   * Fix
   *
   *   esy <anycommand>
   *
   * for cmdliner by injecting "--" so that users are not requied to do that.
   *)
  | Some commandName ->
    if hasCommand commandName
    then runCmdliner Sys.argv
    else
      let argv =
        match Array.to_list Sys.argv with
        | prg::rest -> prg::"--"::rest
        | argv -> argv
      in
      let argv = Array.of_list argv in
      runCmdliner argv

  | _ ->
    runCmdliner Sys.argv
