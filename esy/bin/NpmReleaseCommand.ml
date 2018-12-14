open EsyInstall
open Esy

let esyInstallReleaseJs =
  let req = "../../../../bin/esyInstallRelease.js" in
  match NodeResolution.resolve req with
  | Ok path -> path
  | Error (`Msg msg) -> failwith msg

type filterPackages =
  | NoFilter
  | ExcludeById of string list
  | IncludeByPkgSpec of PkgSpec.t list

type config = {
  name : string;
  version : string;
  license : Json.t option;
  description : string option;
  bin : string StringMap.t;
  filterPackages : filterPackages;
}

module OfPackageJson = struct
  type bin =
    | ByList of string list
    | ByName of string
    | ByNameMany of string StringMap.t

  let bin_of_yojson json =
    let open Result.Syntax in
    match json with
    | `String name -> return (ByName name)
    | `List _ ->
      let%bind names = Json.Decode.(list string) json in
      return (ByList names)
    | `Assoc _ ->
      let%bind names = Json.Decode.(stringMap string) json in
      return (ByNameMany names)

    | _ -> error {|"esy.release.bin": expected a string, array or an object|}

  type t = {
    name : string [@default "project"];
    version : string [@default "0.0.0"];
    license : Json.t option [@default None];
    description : string option [@default None];
    esy : esy [@default {release = None}]
  } [@@deriving (of_yojson { strict = false })]

  and esy = {
    release : release option [@default None];
  }

  and release = {
    includePackages : PkgSpec.t list option [@default None];
    releasedBinaries: string list option [@default None];
    bin : bin option [@default None];
    deleteFromBinaryRelease: string list option [@default None];
  }

end

let configure (cfg : Config.t) () =
  let open RunAsync.Syntax in
  let docs = "https://esy.sh/docs/release.html" in
  match cfg.spec.manifest with
  | EsyInstall.ManifestSpec.ManyOpam
  | EsyInstall.ManifestSpec.One (EsyInstall.ManifestSpec.Filename.Opam, _) ->
    errorf "could not create releases without package.json, see %s for details" docs
  | EsyInstall.ManifestSpec.One (EsyInstall.ManifestSpec.Filename.Esy, filename) ->
    let%bind json = Fs.readJsonFile Path.(cfg.spec.path / filename) in
    let%bind pkgJson = RunAsync.ofStringError (OfPackageJson.of_yojson json) in
    match pkgJson.OfPackageJson.esy.release with
    | None -> errorf "no release config found in package.json, see %s for details" docs
    | Some releaseCfg ->
      let%bind filterPackages =
        match releaseCfg.includePackages, releaseCfg.deleteFromBinaryRelease with
        | None, None -> return NoFilter
        | Some f, None -> return (IncludeByPkgSpec f)
        | None, Some f -> return (ExcludeById f)
        | Some _, Some _ ->
          errorf {|both "esy.release.deleteFromBinaryRelease" and "esy.release.includePackages" are specified, which is not allowed|}
      in
      let%bind bin =
        match releaseCfg.bin, releaseCfg.releasedBinaries with
        | None, None ->
          errorf {|missing "esy.release.bin" configuration|}
        | None, Some names
        | Some (OfPackageJson.ByList names), None ->
          let f bin name = StringMap.add name name bin in
          return (List.fold_left ~f ~init:StringMap.empty names)
        | Some (OfPackageJson.ByName name), None ->
          return (StringMap.add name name StringMap.empty)
        | Some (OfPackageJson.ByNameMany bin), None ->
          return bin
        | Some _, Some _ ->
          errorf {|both "esy.release.bin" and "esy.release.releasedBinaries" are specified, which is not allowed|}
      in
      return {
        name = pkgJson.name;
        version = pkgJson.version;
        license = pkgJson.license;
        description = pkgJson.description;
        bin;
        filterPackages;
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
        "{|" ^ name ^ "|}, {|" ^ EsyLib.Path.normalizePathSlashes value ^ "|}")
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

let envspec = {
  EnvSpec.
  buildIsInProgress = false;
  includeCurrentEnv = true;
  includeBuildEnv = false;
  includeNpmBin = true;
  augmentDeps = Some DepSpec.(package self + dependencies self + devDependencies self);
}
let buildspec = {
  BuildSpec.
  build = {mode = Build; deps = DepSpec.(dependencies self);};
  buildLink = Some {mode = Build; deps = DepSpec.(dependencies self);};
  buildRoot = Some {mode = Build; deps = DepSpec.(dependencies self);};
}

let make
  ~ocamlopt
  ~outputPath
  ~concurrency
  (cfg : Config.t)
  (sandbox : BuildSandbox.t)
  root =
  let open RunAsync.Syntax in

  let%lwt () = Logs_lwt.app (fun m -> m "Creating npm release") in
  let%bind releaseCfg = configure cfg () in

  (*
    * Construct a task tree with all tasks marked as immutable. This will make
    * sure all packages are built into a global store and this is required for
    * the release tarball as only globally stored artefacts can be relocated
    * between stores (b/c of a fixed path length).
    *)
  let%bind plan = RunAsync.ofRun (
    BuildSandbox.makePlan
      ~forceImmutable:true
      sandbox
      buildspec
  ) in
  let tasks = BuildSandbox.Plan.all plan in

  let shouldDeleteFromBinaryRelease =
    match releaseCfg.filterPackages with
    | NoFilter -> fun _ _ -> false
    | IncludeByPkgSpec specs -> fun pkgid _buildid ->
      let f spec = PkgSpec.matches root.Package.id spec pkgid in
      let included = List.exists ~f specs in
      not included
    | ExcludeById patterns ->
      let patterns =
        let f pattern = pattern |> Re.Glob.glob |> Re.compile in
        List.map ~f patterns
      in
      let filterOut _pkgid buildid =
        let buildid = BuildId.show buildid in
        List.exists ~f:(fun pattern -> Re.execp pattern buildid) patterns
      in
      filterOut
  in

  (* Make sure all packages are built *)
  let%bind () =
    let%lwt () = Logs_lwt.app (fun m -> m "Building packages") in
    BuildSandbox.build
      ~buildLinked:true
      ~concurrency
      sandbox
      plan
      [root.Package.id]
  in

  let%bind () = Fs.createDir outputPath in

  (* Export builds *)
  let%bind () =

    let%lwt () =
      match releaseCfg.filterPackages with
      | IncludeByPkgSpec specs ->
        let f unused spec =
          let f task = PkgSpec.matches root.id spec task.BuildSandbox.Task.pkg.id in
          match List.exists ~f tasks with
          | true -> unused
          | false -> spec::unused
        in
        begin match List.fold_left ~f ~init:[] specs with
        | [] -> Lwt.return ()
        | unused -> Logs_lwt.warn (fun m ->
            m {|found unused package specs in "esy.release.includePackages": %a|}
            (Fmt.(list ~sep:(unit ", ") PkgSpec.pp)) unused
          )
        end
      | _ -> Lwt.return ()
    in

    let%lwt () = Logs_lwt.app (fun m -> m "Exporting built packages") in
    let f (task : BuildSandbox.Task.t) =
      let id = Scope.id task.scope in
      if shouldDeleteFromBinaryRelease task.pkg.id id
      then
        let%lwt () = Logs_lwt.app (fun m -> m "Skipping %a" PackageId.ppNoHash task.pkg.id) in
        return ()
      else
        let buildPath = BuildSandbox.Task.installPath cfg task in
        let outputPrefixPath = Path.(outputPath / "_export") in
        BuildSandbox.exportBuild ~cfg ~outputPrefixPath buildPath
    in
    RunAsync.List.mapAndWait
      ~concurrency:8
      ~f
      tasks
  in

  let%bind () =

    let%lwt () = Logs_lwt.app (fun m -> m "Configuring release") in
    let%bind bindings = RunAsync.ofRun (
      BuildSandbox.env
        ~forceImmutable:true
        envspec
        buildspec
        sandbox
        root.Package.id
    ) in
    let binPath = Path.(outputPath / "bin") in
    let%bind () = Fs.createDir binPath in

    (* Emit wrappers for released binaries *)
    let%bind () =
      let bindings = Scope.SandboxEnvironment.Bindings.render cfg.buildCfg bindings in
      let%bind env = RunAsync.ofStringError (Environment.Bindings.eval bindings) in

      let generateBinaryWrapper stagePath (publicName, innerName) =
        let resolveBinInEnv ~env prg =
          let path =
            let v = match StringMap.find_opt "PATH" env with
              | Some v  -> v
              | None -> ""
            in
            String.split_on_char (System.Environment.sep ()).[0] v
          in RunAsync.ofRun (Run.ofBosError (Cmd.resolveCmd path prg))
        in
        let%bind namePath = resolveBinInEnv ~env innerName in
        (* Create the .ml file that we will later compile and write it to disk *)
        let data = makeBinWrapper ~environment:bindings ~bin:(EsyLib.Path.normalizePathSlashes namePath) in
        let mlPath = Path.(stagePath / (innerName ^ ".ml")) in
        let%bind () = Fs.writeFile ~data mlPath in
        (* Compile the wrapper to a binary *)
        let compile = Cmd.(
          v (EsyLib.Path.normalizePathSlashes (p ocamlopt))
          % "-o" % EsyLib.Path.normalizePathSlashes (p Path.(binPath / publicName))
          % "unix.cmxa" % "str.cmxa"
          % EsyLib.Path.normalizePathSlashes (p mlPath)
        ) in
        (* Needs to have ocaml in environment *)
        let%bind env =
          match System.Platform.host with
          | Windows ->
            let currentPath = Sys.getenv("PATH") in
            let userPath = EsyBash.getBinPath () in
            let normalizedOcamlPath = ocamlopt |> Path.parent |> Path.showNormalized in
            let override =
              let sep = System.Environment.sep () in
              let path = String.concat sep [Path.show userPath; normalizedOcamlPath; currentPath] in
              StringMap.(add "PATH" path empty)
            in
            return (ChildProcess.CurrentEnvOverride override)
          | _ ->
            return ChildProcess.CurrentEnv
        in
        ChildProcess.run ~env compile
      in
      let%bind () =
        Fs.withTempDir (fun stagePath ->
          RunAsync.List.mapAndWait
            ~f:(generateBinaryWrapper stagePath)
            (StringMap.bindings releaseCfg.bin)
        )
      in
      (* Replace the storePath with a string of equal length containing only _ *)
      let (origPrefix, destPrefix) =
        let nextStorePrefix =
          String.make (String.length (Path.show cfg.buildCfg.storePath)) '_'
        in
        (cfg.buildCfg.storePath, Path.v nextStorePrefix)
      in
      let%bind () = Fs.writeFile ~data:(Path.show destPrefix) Path.(binPath / "_storePath") in
      RewritePrefix.rewritePrefix ~origPrefix ~destPrefix binPath
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
            let f (publicName, _innerName) = publicName, `String ("bin/" ^ publicName) in
            List.map ~f (StringMap.bindings releaseCfg.bin)
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
      Fs.copyFile ~src:esyInstallReleaseJs ~dst:Path.(outputPath / "esyInstallRelease.js")
    in

    return ()
  in

  let%lwt () = Logs_lwt.app (fun m -> m "Done!") in
  return ()

let run (proj : Project.WithWorkflow.t) () =
  let open RunAsync.Syntax in

  let%bind solved = Project.solved proj in
  let%bind fetched = Project.fetched proj in
  let%bind configured = Project.configured proj in

  let%bind outputPath =
    let outputDir = "_release" in
    let outputPath = Path.(proj.projcfg.cfg.buildCfg.projectPath / outputDir) in
    let%bind () = Fs.rmPath outputPath in
    return outputPath
  in

  let%bind () =

    let%bind () =
      Project.buildDependencies
        ~buildLinked:true
        ~buildDevDependencies:true
        proj
        configured.Project.WithWorkflow.plan
        configured.Project.WithWorkflow.root.pkg
    in
    Project.buildPackage
      ~quiet:true
      ~buildOnly:false
      proj.projcfg
      fetched.Project.sandbox
      configured.Project.WithWorkflow.plan
      configured.Project.WithWorkflow.root.pkg
  in

  let%bind ocamlopt =
    let%bind p = Project.WithWorkflow.ocaml proj in
    return Path.(p / "bin" / "ocamlopt")
  in

  make
    ~ocamlopt
    ~outputPath
    ~concurrency:EsyRuntime.concurrency
    proj.projcfg.ProjectConfig.cfg
    fetched.Project.sandbox
    (Solution.root solved.Project.solution)
