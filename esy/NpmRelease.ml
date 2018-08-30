module StringSet = Set.Make(String)

type config = {
  name : string;
  version : string;
  license : Json.t option;
  description : string option;
  releasedBinaries : string list;
  deleteFromBinaryRelease : string list;
}

let makeBinWrapper ~bin ~(environment : Environment.Bindings.t) =
  let environmentString =
    environment
    |> Environment.renderToList
    |> List.filter ~f:(fun (name, _) ->
        match name with
        | "cur__original_root" | "cur__root" -> false
        | _ -> true
      )
    |> List.map ~f:(fun (name, value) ->
        "\"" ^ name ^ "\", \"" ^ Environment.escapeDoubleQuote value ^ "\"")
    |> String.concat ";"
  in
  Printf.sprintf {|
    let curEnvMap =
      let curEnv = Unix.environment () in
      let table = Hashtbl.create (Array.length curEnv) in
      let f item =
        try (
          let idx = String.index item '=' in
          let name = String.sub item 0 idx in
          let value = String.sub item (idx + 1) (String.length item - idx - 1) in
          Hashtbl.replace table name value
        ) with Not_found -> ()
      in
      Array.iter f curEnv;
      table;;

    let env =
      let findVarRe = Str.regexp "\\$\\([a-zA-Z0-9_]+\\)" in
      let replace v =
        let name = Str.matched_group 1 v in
        try Hashtbl.find curEnvMap name
        with Not_found -> ""
      in
      let f (name, value) =
        let value = Str.global_substitute findVarRe replace value in
        Hashtbl.replace curEnvMap name value
      in
      Array.iter f [|%s|];
      let f name value items = (name ^ "=" ^ value)::items in
      Array.of_list (Hashtbl.fold f curEnvMap []);;

    let () =
      if Array.length Sys.argv = 2 && Sys.argv.(1) = "----where" then
        print_endline "%s"
      else if Array.length Sys.argv = 2 && Sys.argv.(1) = "----env" then
        Array.iter print_endline env
      else (
        let program = "%s" in
        Sys.argv.(0) <- program;
        Unix.execve program Sys.argv env
      )
  |} environmentString bin bin

let configure ~(sandbox : Sandbox.t) =
  let open RunAsync.Syntax in
  match%bind Manifest.ofDir sandbox.buildConfig.projectPath with
  | None -> error "no manifest found"
  | Some (manifest, _) ->
    let%bind releaseCfg =
      RunAsync.ofOption ~err:"no release config found" (Manifest.release manifest)
    in
    return {
      name = Manifest.name manifest;
      version = Manifest.version manifest;
      license = Manifest.license manifest;
      description = Manifest.description manifest;
      releasedBinaries = releaseCfg.Manifest.Release.releasedBinaries;
      deleteFromBinaryRelease = releaseCfg.Manifest.Release.deleteFromBinaryRelease;
    }

let dependenciesForRelease (task : Task.t) =
  let f deps dep = match dep with
    | Task.Dependency depTask
    | Task.BuildTimeDependency depTask ->
      begin match Task.sourceType depTask with
      | Manifest.SourceType.Immutable -> (depTask, dep)::deps
      | _ -> deps
      end
    | Task.DevDependency _ -> deps
  in
  Task.dependencies task
  |> List.fold_left ~f ~init:[]
  |> List.rev

let make ~ocamlopt ~esyInstallRelease ~outputPath ~concurrency ~(sandbox : Sandbox.t) =
  let open RunAsync.Syntax in


  let%lwt () = Logs_lwt.app (fun m -> m "Creating npm release") in
  let%bind releaseCfg = configure ~sandbox in

  (*
    * Construct a task tree with all tasks marked as immutable. This will make
    * sure all packages are built into a global store and this is required for
    * the release tarball as only globally stored artefacts can be relocated
    * between stores (b/c of a fixed path length).
    *)
  let%bind task = RunAsync.ofRun (Task.ofSandbox ~forceImmutable:true sandbox) in

  let tasks = Task.Graph.traverse ~traverse:dependenciesForRelease task in

  let shouldDeleteFromBinaryRelease =
    let patterns =
      let f pattern = pattern |> Re.Glob.glob |> Re.compile in
      List.map ~f releaseCfg.deleteFromBinaryRelease
    in
    let filterOut id =
      List.exists ~f:(fun pattern -> Re.execp pattern id) patterns
    in
    filterOut
  in

  (*
    * Find all tasks which are originated from package in dev mode.
    * We need to force their build and then do a cleanup after release.
    *)
  let devModeIds =
    let f s task =
      match Task.sourceType task with
      | Manifest.SourceType.Immutable -> s
      | Manifest.SourceType.Transient -> StringSet.add (Task.id task) s
    in
    List.fold_left
      ~init:StringSet.empty
      ~f
      tasks
  in

  (* Make sure all packages are built *)
  let%bind () =
    let%lwt () = Logs_lwt.app (fun m -> m "Building packages") in
    Build.buildAll
      ~concurrency
      ~buildOnly:`No
      ~force:(`Select devModeIds)
      sandbox
      task
  in

  let%bind () = Fs.createDir outputPath in

  (* Export builds *)
  let%bind () =
    let%lwt () = Logs_lwt.app (fun m -> m "Exporting built packages") in
    let queue = LwtTaskQueue.create ~concurrency:8 () in
    let f (task : Task.t) =
      if shouldDeleteFromBinaryRelease (Task.id task)
      then
        let%lwt () = Logs_lwt.app (fun m -> m "Skipping %s" (Task.id task)) in
        return ()
      else
        let buildPath = Sandbox.Path.toPath sandbox.buildConfig (Task.installPath task) in
        let outputPrefixPath = Path.(outputPath / "_export") in
        LwtTaskQueue.submit queue (fun () -> Task.exportBuild ~cfg:sandbox.cfg ~outputPrefixPath buildPath)
    in
    tasks |> List.map ~f |> RunAsync.List.waitAll
  in

  let%bind () =

    let%lwt () = Logs_lwt.app (fun m -> m "Configuring release") in

    let%bind bindings = RunAsync.ofRun (
      let open Run.Syntax in
      let pkg = sandbox.Sandbox.root in
      let sandbox =
        let root = {
          Sandbox.
          id = "__release_env__";
          name = "release-env";
          version = pkg.version;
          dependencies = [Sandbox.Dependency pkg];
          build = {
            Manifest.Build.
            sourceType = Manifest.SourceType.Transient;
            buildEnv = Manifest.Env.empty;
            buildCommands = Manifest.Build.EsyCommands None;
            installCommands = Manifest.Build.EsyCommands None;
            buildType = Manifest.BuildType.OutOfSource;
            patches = [];
            substs = [];
            exportedEnv = [];
          };
          sourcePath = pkg.sourcePath;
          resolution = None;
        } in
        {sandbox with root}
      in
      let%bind task = Task.ofSandbox ~forceImmutable:true sandbox in
      let%bind bindings = Task.sandboxEnv task in
      return bindings
    ) in

    let binPath = Path.(outputPath / "bin") in
    let%bind () = Fs.createDir binPath in

    (* Emit wrappers for released binaries *)
    let%bind () =
      let bindings = Sandbox.Environment.Bindings.render sandbox.buildConfig bindings in
      let%bind env = RunAsync.ofStringError (Environment.Bindings.eval bindings) in

      let generateBinaryWrapper stagePath name =
        let resolveBinInEnv ~env prg =
          let path =
            let v = match StringMap.find_opt "PATH" env with
              | Some v  -> v
              | None -> ""
            in
            String.split_on_char ':' v
          in RunAsync.ofRun (Run.ofBosError (Cmd.resolveCmd path prg))
        in
        let%bind namePath = resolveBinInEnv ~env name in
        (* Create the .ml file that we will later compile and write it to disk *)
        let data = makeBinWrapper ~environment:bindings ~bin:namePath in
        let mlPath = Path.(stagePath / (name ^ ".ml")) in
        let%bind () = Fs.writeFile ~data mlPath in
        (* Compile the wrapper to a binary *)
        let compile = Cmd.(
          v (p ocamlopt)
          % "-o" % p Path.(binPath / name)
          % "unix.cmxa" % "str.cmxa"
          % p mlPath
        ) in
        ChildProcess.run compile
      in
      let%bind () =
        Fs.withTempDir (fun stagePath ->
          releaseCfg.releasedBinaries
          |> List.map ~f:(generateBinaryWrapper stagePath)
          |> RunAsync.List.waitAll
        )
      in
      (* Replace the storePath with a string of equal length containing only _ *)
      let (origPrefix, destPrefix) =
        let nextStorePrefix =
          String.make (String.length (Path.toString sandbox.buildConfig.storePath)) '_'
        in
        (sandbox.buildConfig.storePath, Path.v nextStorePrefix)
      in
      let%bind () = Fs.writeFile ~data:(Path.toString destPrefix) Path.(binPath / "_storePath") in
      Task.rewritePrefix ~cfg:sandbox.cfg ~origPrefix ~destPrefix binPath
    in

    (* Emit package.json *)
    let%bind () =
      let pkgJson =
        let items = [
          "name", `String releaseCfg.name;
          "version", `String releaseCfg.version;
          "scripts", `Assoc [
            "postinstall", `String "node ./esyInstallRelease.js"
          ];
          "bin", `Assoc (
            let f name = name, `String ("bin/" ^ name) in
            List.map ~f releaseCfg.releasedBinaries
          )
        ]
        in
        let items = match releaseCfg.license with
          | Some license -> ("license", license)::items
          | None -> items
        in
        let items = match releaseCfg.description with
          | Some description -> ("description", `String description)::items
          | None -> items
        in
        `Assoc items
      in
      let data = Yojson.Safe.pretty_to_string pkgJson in
      Fs.writeFile ~data Path.(outputPath / "package.json")
    in

    let%bind () =
      Fs.copyFile ~src:esyInstallRelease ~dst:Path.(outputPath / "esyInstallRelease.js")
    in

    return ()
  in

  let%lwt () = Logs_lwt.app (fun m -> m "Done!") in
  return ()
