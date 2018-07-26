module StringSet = Set.Make(String)

type config = {
  name : string;
  version : string;
  license : Json.t option;
  description : string option;
  releasedBinaries : string list;
  deleteFromBinaryRelease : string list;
}

let makeBinWrapper ~bin ~(environment : Environment.t) =
  let environmentString =
    environment
    |> List.filter ~f:(fun {Environment. name; _} ->
        match name with
        | "cur__original_root" | "cur__root" -> false
        | _ -> true
      )
    |> List.map ~f:(fun {Environment. name; value; _} ->
        match value with
        | Environment.Value value ->
          "\"" ^ name ^ "\", \"" ^ Environment.escapeDoubleQuote value ^ "\""
        | Environment.ExpandedValue value ->
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
      table

    let () =
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
        Array.of_list (Hashtbl.fold f curEnvMap [])
      in
      Unix.execve "%s" Sys.argv env
  |} environmentString bin

let configure ~(cfg : Config.t) =
  let open RunAsync.Syntax in
  let%bind manifestOpt = Manifest.ofDir cfg.Config.sandboxPath in
  let%bind manifest = match manifestOpt with
    | Some (Manifest.Esy manifest, _path) -> return manifest
    | Some (Manifest.Opam _, _path) ->
      error "packages with opam manifests do not support release"
    | None -> error "no manifest found"
  in
  let%bind releaseCfg =
    RunAsync.ofOption ~err:"no release config found" (
      let open Option.Syntax in
      let%bind esyManifest = manifest.Manifest.Esy.esy in
      let%bind releaseCfg = esyManifest.Manifest.EsyManifest.release in
      return releaseCfg
    )
  in
  return {
    name = manifest.Manifest.Esy.name;
    version = manifest.version;
    license = manifest.license;
    description = manifest.description;
    releasedBinaries = releaseCfg.Manifest.EsyReleaseConfig.releasedBinaries;
    deleteFromBinaryRelease = releaseCfg.Manifest.EsyReleaseConfig.deleteFromBinaryRelease;
  }

let dependenciesForRelease (task : Task.t) =
  let f deps dep = match dep with
    | Task.Dependency ({
        sourceType = Manifest.SourceType.Immutable;
        _
      } as task)
    | Task.BuildTimeDependency ({
          sourceType = Manifest.SourceType.Immutable; _
        } as task) ->
      (task, dep)::deps
    | Task.Dependency _
    | Task.DevDependency _
    | Task.BuildTimeDependency _ -> deps
  in
  task.dependencies
  |> List.fold_left ~f ~init:[]
  |> List.rev

let make ~esyInstallRelease ~outputPath ~concurrency ~cfg ~sandbox =
  let open RunAsync.Syntax in


  let%lwt () = Logs_lwt.app (fun m -> m "Creating npm release") in
  let%bind releaseCfg = configure ~cfg in

  (*
    * Construct a task tree with all tasks marked as immutable. This will make
    * sure all packages are built into a global store and this is required for
    * the release tarball as only globally stored artefacts can be relocated
    * between stores (b/c of a fixed path length).
    *)
  let%bind task = RunAsync.ofRun (Task.ofPackage ~forceImmutable:true sandbox.Sandbox.root) in

  (* Path to ocamlopt executable *)
  let%bind ocamlopt = RunAsync.ofRun (
      let open Run.Syntax in
      let%bind ocaml =
        match Task.DependencyGraph.find ~f:(fun task -> task.pkg.name = "ocaml") task with
        | Some(ocaml) -> return ocaml
        | None -> error "ocaml isn't available in the sandbox"
      in
      let ocamlopt =
        let installPath = Config.Path.toPath cfg ocaml.Task.paths.installPath in
        Path.(installPath / "bin" / "ocamlopt")
      in
      return ocamlopt
    ) in

  let tasks = Task.DependencyGraph.traverse ~traverse:dependenciesForRelease task in

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
      match task.Task.pkg.sourceType with
      | Manifest.SourceType.Immutable -> s
      | Manifest.SourceType.Transient -> StringSet.add task.id s
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
      cfg task
  in

  let%bind () = Fs.createDir outputPath in

  (* Export builds *)
  let%bind () =
    let%lwt () = Logs_lwt.app (fun m -> m "Exporting built packages") in
    let queue = LwtTaskQueue.create ~concurrency:8 () in
    let f (task : Task.t) =
      if shouldDeleteFromBinaryRelease task.id
      then
        let%lwt () = Logs_lwt.app (fun m -> m "Skipping %s" task.id) in
        return ()
      else
        let buildPath = Config.Path.toPath cfg task.paths.installPath in
        let outputPrefixPath = Path.(outputPath / "_export") in
        LwtTaskQueue.submit queue (fun () -> Task.exportBuild ~cfg ~outputPrefixPath buildPath)
    in
    tasks |> List.map ~f |> RunAsync.List.waitAll
  in

  let%bind () =

    let%lwt () = Logs_lwt.app (fun m -> m "Configuring release") in

    let%bind env = RunAsync.ofRun (
        let open Run.Syntax in
        let pkg = sandbox.Sandbox.root in
        let synPkg = {
          Package.
          id = "__release_env__";
          name = "release-env";
          version = pkg.version;
          dependencies = [Package.Dependency pkg];
          sourceType = Manifest.SourceType.Transient;
          sandboxEnv = pkg.sandboxEnv;
          buildEnv = Manifest.Env.empty;
          build = Package.EsyBuild {
              buildCommands = None;
              installCommands = None;
              buildType = Manifest.BuildType.OutOfSource;
            };
          exportedEnv = [];
          sourcePath = pkg.sourcePath;
          resolution = None;
        } in
        let%bind task = Task.ofPackage
            ~initTerm:(Some "$TERM")
            ~initPath:"$PATH"
            ~initManPath:"$MAN_PATH"
            ~initCamlLdLibraryPath:"$CAML_LD_LIBRARY_PATH"
            ~forceImmutable:true
            ~overrideShell:false
            synPkg
        in
        return task.Task.env
      ) in

    let binPath = Path.(outputPath / "bin") in
    let%bind () = Fs.createDir binPath in

    (* Emit wrappers for released binaries *)
    let%bind () =
      let%bind bindings = RunAsync.ofRun (Environment.bindToConfig cfg (Environment.Closed.bindings env)) in
      let%bind value = RunAsync.ofRun (Environment.Value.bindToConfig cfg (Environment.Closed.value env)) in

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
        let%bind namePath = resolveBinInEnv ~env:value name in
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
        let nextStorePrefix = String.make (String.length (Path.toString Config.(cfg.storePath))) '_' in
        (Config.(cfg.storePath), Path.v nextStorePrefix)
      in
      let%bind () = Fs.writeFile ~data:(Path.to_string destPrefix) Path.(binPath / "_storePath") in
      Task.rewritePrefix ~cfg ~origPrefix ~destPrefix binPath
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
