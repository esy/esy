module StringSet = Set.Make(String)
module Manifest = Package.Manifest
module EsyManifest = Package.EsyManifest
module EsyReleaseConfig = Package.EsyReleaseConfig
module Store = EsyLib.Store

type config = {
  name : string;
  version : string;
  license : Json.t option;
  description : string option;
  releasedBinaries : string list;
  deleteFromBinaryRelease : string list;
}

let shellSafe s =
  let escape = function
    | '-' -> 'h'
    | '.' -> 'd'
    | '_' -> '_'
    | '@' -> 'a'
    | c -> c
  in
  s |> String.uppercase_ascii |> String.map escape

let makeBinWrapperChrome ~cfg ~bin ~execute =
  let id = cfg.name ^ "-" ^ cfg.version in
  Printf.sprintf {|#!/bin/bash

ESY__PACKAGE_NAME="%s"
ESY__BIN_NAME="%s"

IS_RELEASE_BIN_ENV_SOURCED="ENV__${ESY__PACKAGE_NAME}__${ESY__BIN_NAME}"
IS_RELEASE_ENV_SOURCED="ENV__${ESY__PACKAGE_NAME}"

printError() {
  echo >&2 "ERROR:";
  echo >&2 "$0 command is not installed correctly. ";
  TROUBLESHOOTING="When installing <package_name>, did you see any errors in the log? "
  TROUBLESHOOTING="$TROUBLESHOOTING - What does (which <binary_name>) return? "
  TROUBLESHOOTING="$TROUBLESHOOTING - Please file a github issue on <package_name>'s repo."
  echo >&2 "$TROUBLESHOOTING";
}

if [ -z ${!IS_RELEASE_BIN_ENV_SOURCED+x} ]; then
  if [ -z ${!IS_RELEASE_ENV_SOURCED+x} ]; then

    #
    # Define $SCRIPTDIR
    #

    SOURCE="${BASH_SOURCE[0]}"
    while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
      SCRIPTDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
      SOURCE="$(readlink "$SOURCE")"
      # if $SOURCE was a relative symlink, we need to resolve it relative to the
      # path where the symlink file was located
      [[ $SOURCE != /* ]] && SOURCE="$SCRIPTDIR/$SOURCE"
    done
    SCRIPTDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

    #
    # Esy utility functions
    #

    esyStrLength() {
      # run in a subprocess to override $LANG variable
      LANG=C /bin/bash -c 'echo "${#0}"' "$1"
    }

    esyRepeatCharacter() {
      local chToRepeat="$1"
      local times="$2"
      printf "%%0.s$chToRepeat" $(seq 1 "$times")
    }

    esyGetStorePathFromPrefix() {
      local prefix="$1"
      # Remove trailing slash if any.
      prefix="${prefix%%/}"

      prefixLength=$(esyStrLength "$prefix")
      paddingLength=$((ESY__STORE_PADDING_LENGTH - prefixLength))

      # Discover how much of the reserved relocation padding must be consumed.
      if [ "$paddingLength" -lt "0" ]; then
        echo "$prefix is too deep inside filesystem, Esy won't be able to relocate binaries"
        exit 1;
      fi

      padding=$(esyRepeatCharacter '_' "$paddingLength")
      echo "$prefix/$ESY__STORE_VERSION$padding"
    }

    #
    # Esy Release Env
    #

    ESY__STORE_VERSION="%s"
    ESY__STORE_PADDING_LENGTH="%d"
    ESY__RELEASE=$(dirname "$SCRIPTDIR")

    ESY__STORE=$(esyGetStorePathFromPrefix "$ESY__RELEASE")
    if [ $? -ne 0 ]; then
      echo >&2 "error: $ESY__STORE"
      exit 1
    fi

    export ESY__RELEASE
    export ESY__STORE

    source "$ESY__RELEASE/releaseEnv"

    export "$IS_RELEASE_ENV_SOURCED"="sourced"
    export "$IS_RELEASE_BIN_ENV_SOURCED"="sourced"
  fi

  %s

else
  printError;
  exit 1;
fi
|} (shellSafe id) (shellSafe bin) Store.version Store.maxStorePaddingLength execute

let makeBinWrapper ~cfg ~bin =
  let execute = Printf.sprintf {|
    BINNAME="%s"

    command -v ${BINNAME} >/dev/null 2>&1 || {
      printError;
      exit 1;
    }

    if [ "$1" == "----where" ]; then
      which "${BINNAME}"
    else
      exec "${BINNAME}" "$@"
    fi
  |} bin in
  makeBinWrapperChrome ~cfg ~bin ~execute

let makeSandboxBin ~cfg ~bin =
  let releasedBinariesStr = String.concat ", " cfg.releasedBinaries in
  let execute = Printf.sprintf {|
function execute() {
  local name="%s"
  local releasedBinaries="%s"
  local bin="%s"

  if [[ "$1" == ""  ]]; then
    cat << EOF
Welcome to ${name}

The following commands are available: ${releasedBinaries}

Note:

- ${bin} bash

  Starts a sandboxed bash shell with access to the ${name} environment.

  Running builds and scripts from within "${bin} bash" will typically increase
  the performance as environment is already sourced.

- <command name> ----where

  Prints the location of <command name>

  Example: ocaml ----where

EOF
  else
    if [ "$1" == "bash" ]; then
      # Important to pass --noprofile, and --rcfile so that the user's
      # .bashrc doesn't run and the npm global packages don't get put in front
      # of the already constructed PATH.
      bash --noprofile --rcfile <(echo "export PS1=\"[${name} sandbox] \"")
    else
      echo "Invalid argument $1, type ${bin} for help"
    fi
  fi
}

execute "$@"
  |} cfg.name releasedBinariesStr bin in
  makeBinWrapperChrome ~cfg ~bin ~execute

let configure ~(cfg : Config.t) =
  let open RunAsync.Syntax in
  let%bind manifestOpt = Manifest.ofDir cfg.Config.sandboxPath in
  let%bind manifest = match manifestOpt with
  | Some (manifest, _path, _json) -> return manifest
  | None -> error "no manifest found"
  in
  let%bind releaseCfg =
    RunAsync.ofOption ~err:"no release config found" (
      let open Option.Syntax in
      let%bind esyManifest = manifest.Manifest.esy in
      let%bind releaseCfg = esyManifest.EsyManifest.release in
      return releaseCfg
    )
  in
  return {
    name = manifest.Manifest.name;
    version = manifest.Manifest.version;
    license = manifest.Manifest.license;
    description = manifest.Manifest.description;
    releasedBinaries = releaseCfg.EsyReleaseConfig.releasedBinaries;
    deleteFromBinaryRelease = releaseCfg.EsyReleaseConfig.deleteFromBinaryRelease;
  }

let dependenciesForRelease (task : Task.t) =
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
      | Package.SourceType.Immutable -> s
      | Package.SourceType.Development -> StringSet.add task.id s
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
        let buildPath = Config.ConfigPath.toPath cfg task.paths.installPath in
        let outputPrefixPath = Path.(outputPath / "_export") in
        LwtTaskQueue.submit queue (fun () -> Task.exportBuild ~cfg ~outputPrefixPath buildPath)
    in
    tasks |> List.map ~f |> RunAsync.List.waitAll
  in

  let%bind () =

    let%lwt () = Logs_lwt.app (fun m -> m "Configuring release") in

    let binPath = Path.(outputPath / "bin") in
    let%bind () = Fs.createDir binPath in

    (* Emit wrappers for released binaries *)
    let%bind () =
      let generateBinaryWrapper name =
        let data = makeBinWrapper ~cfg:releaseCfg ~bin:name in
        let%bind () = Fs.writeFile ~data Path.(binPath / name) in
        let%bind () = Fs.chmod 0o755 Path.(binPath / name) in
        return ()
      in
      releaseCfg.releasedBinaries
      |> List.map ~f:generateBinaryWrapper
      |> RunAsync.List.waitAll
    in

    let sandboxEntryBin = releaseCfg.name ^ "-sandbox" in

    (* Emit sandbox entry script *)
    let%bind () =
      let data = makeSandboxBin ~cfg:releaseCfg ~bin:sandboxEntryBin in
      let%bind () = Fs.writeFile ~data Path.(binPath / sandboxEntryBin) in
      let%bind () = Fs.chmod 0o755 Path.(binPath / sandboxEntryBin) in
      return ()
    in

    (* Emit release env *)
    let%bind () =
      let%bind data = RunAsync.ofRun (
        let open Run.Syntax in

        let%bind env =
          let pkg = sandbox.Sandbox.root in
          let synPkg = {
            Package.
            id = "__release_env__";
            name = "release-env";
            version = pkg.version;
            dependencies = [Package.Dependency pkg];
            buildCommands = None;
            installCommands = None;
            buildType = Package.BuildType.OutOfSource;
            sourceType = Package.SourceType.Development;
            exportedEnv = [];
            sandboxEnv = pkg.sandboxEnv;
            sourcePath = pkg.sourcePath;
            resolution = None;
          } in
          let%bind task = Task.ofPackage
            ~term:(Some "$TERM")
            ~forceImmutable:true
            ~overrideShell:false
            synPkg
          in
          return (Environment.Closed.bindings task.Task.env)
        in

        Environment.renderToShellSource
          ~localStorePath:(Path.v "/local/store/does/not/exist")
          ~storePath:(Path.v "$ESY__STORE")
          ~sandboxPath:(Path.v "$ESY__RELEASE")
        env
      ) in
      let%bind () = Fs.writeFile ~data Path.(outputPath / "releaseEnv") in
      return ()
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
            List.map ~f (sandboxEntryBin::releaseCfg.releasedBinaries)
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
