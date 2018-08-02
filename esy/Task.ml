(**
 * Build task.
 *
 * TODO: Reconcile with BuildTask, right now we just reuse types & code
 * from there but it probably should live here instead. Fix that after we decide
 * on better package boundaries.
*)

module Store = EsyLib.Store

let toOpamName name =
  match Astring.String.cut ~sep:"@opam/" name with
  | Some ("", name) -> name
  | _ -> name

let toOCamlVersion version =
  match String.split_on_char '.' version with
  | major::minor::patch::[] ->
    let patch =
      let v = try int_of_string patch with _ -> 0 in
      if v < 1000 then v else v / 1000
    in
    major ^ ".0" ^ minor ^ "." ^ (string_of_int patch)
  | _ -> version

let renderCommandExpr ?name ~platform ~scope expr =
  let pathSep =
    match platform with
    | System.Platform.Unknown
    | System.Platform.Darwin
    | System.Platform.Linux
    | System.Platform.Unix
    | System.Platform.Windows
    | System.Platform.Cygwin -> "/"
  in
  let colon =
    match name, platform with
    (* a special case for cygwin + OCAMLPATH: it is expected to use ; as separator *)
    | Some "OCAMLPATH", (System.Platform.Linux | Darwin | Unix | Unknown) -> ":"
    | Some "OCAMLPATH", (Cygwin | Windows) -> ";"
    | _, (Linux | Darwin | Unix | Unknown | Cygwin) -> ":"
    | _, Windows -> ";"
  in
  let scope name =
    match name with
    | None, "os" -> Some (EsyCommandExpression.string (System.Platform.show platform))
    | _ -> scope name
  in
  Run.ofStringError (EsyCommandExpression.render ~pathSep ~colon ~scope expr)

module CommandList = struct
  type t =
    string list list
    [@@deriving (show, eq, ord)]

  let make v = v

  let render ~platform ~env ~scope (commands : Manifest.CommandList.t) =
    let open Run.Syntax in
    let env = Environment.Closed.value env in
    let envScope name =
      Environment.Value.find name env
    in
    match commands with
    | None -> Ok []
    | Some commands ->
      let renderCommand =
        let render v =
          let%bind v = renderCommandExpr ~platform ~scope v in
          ShellParamExpansion.render ~scope:envScope v
        in
        function
        | Manifest.CommandList.Command.Parsed args ->
          Result.List.map ~f:render args
        | Manifest.CommandList.Command.Unparsed string ->
          let%bind string = render string in
          let%bind args = ShellSplit.split string in
          return args
      in
      match Result.List.map ~f:renderCommand commands with
      | Ok commands -> Ok commands
      | Error err -> Error err

end

module Scope = struct
  type t =
    EsyCommandExpression.Value.t StringMap.t
    [@@deriving eq, ord]

  let pp fmt _v = Fmt.unit "<scope>" fmt ()
end

type t = {
  id : string;
  pkg : Package.t [@printer fun fmt pkg -> Fmt.string fmt pkg.Package.id];

  buildCommands : CommandList.t;
  installCommands : CommandList.t;

  env : Environment.Closed.t;
  globalEnv : Environment.binding list;
  localEnv : Environment.binding list;
  paths : paths;

  sourceType : Manifest.SourceType.t;

  dependencies : dependency list;

  platform : System.Platform.t;
  scope : Scope.t;
}
[@@deriving (show, eq, ord)]

and paths = {
  rootPath : Config.Path.t;
  sourcePath : Config.Path.t;
  buildPath : Config.Path.t;
  buildInfoPath : Config.Path.t;
  stagePath : Config.Path.t;
  installPath : Config.Path.t;
  logPath : Config.Path.t;
}
[@@deriving show]

and dependency =
  | Dependency of t
  | DevDependency of t
  | BuildTimeDependency of t
[@@deriving (show, eq, ord)]

type task = t
type task_dependency = dependency

let lookupInScope ?cfg bindings (namespace, name) =
  let key =
    match namespace, name with
    | Some namespace, name -> namespace ^ "." ^ name
    | None, name -> name
  in
  match cfg, StringMap.find key bindings with
  | Some cfg, Some (EsyCommandExpression.Value.String v) ->
    let v = Config.Value.v v in
    let v = Config.Value.toString cfg v in
    Some (EsyCommandExpression.string v)
  | Some _, Some v -> Some v
  | None, Some v -> Some v
  | _, None ->
    begin match name with
    | "installed" -> Some (EsyCommandExpression.bool false)
    | _ -> None
    end

let renderExpression ~cfg ~task expr =
  renderCommandExpr ~platform:task.platform ~scope:(lookupInScope ~cfg task.scope) expr

module DependencySet = Set.Make(struct
  type t = dependency
  let compare = compare_dependency
end)

let taskOf (dep : dependency) =
  match dep with
  | Dependency task -> task
  | DevDependency task -> task
  | BuildTimeDependency task -> task

let buildId
  (rootPkg : Package.t)
  (pkg : Package.t)
  (dependencies : dependency list) =

  let hashCommands (commands : Manifest.commands) =
    match commands with
    | Manifest.EsyCommands commands ->
      Manifest.CommandList.show commands
    | Manifest.OpamCommands commands ->
      let commandsToString (commands : OpamTypes.command list) =
        let argsToString (args : OpamTypes.arg list) =
          let f ((arg, filter) : OpamTypes.arg) =
            match arg, filter with
            | OpamTypes.CString arg, None
            | OpamTypes.CIdent arg, None -> arg
            | OpamTypes.CString arg, Some filter
            | OpamTypes.CIdent arg, Some filter ->
              let filter = OpamFilter.to_string filter in
              arg ^ " {" ^ filter ^ "}"
          in
          args
          |> List.map ~f
          |> String.concat " "
        in
        let f ((args, filter) : OpamTypes.command) =
          match filter with
          | Some filter ->
            let filter = OpamFilter.to_string filter in
            let args = argsToString args in
            args ^ " {" ^ filter ^ "}"
          | None ->
          argsToString args
        in
        commands
        |> List.map ~f
        |> String.concat ";"
      in
      commandsToString commands
  in

  let patchesToString patches =
    let f = function
      | path, None -> Path.toString path
      | path, Some filter ->
        let path = Path.toString path in
        path ^ " {" ^ (OpamFilter.to_string filter) ^ "}"
    in
    patches
    |> List.map ~f
    |> String.concat "__SEP__"
  in

  let digest acc update = Digest.string (acc ^ "--" ^ update) in
  let id =
    List.fold_left ~f:digest ~init:"" [
      hashCommands pkg.buildCommands;
      hashCommands pkg.installCommands;
      patchesToString pkg.patches;
      Manifest.BuildType.show pkg.buildType;
      Manifest.Env.show pkg.buildEnv;
      Manifest.Env.show rootPkg.sandboxEnv;
    ]
  in
  let id =
    List.fold_left ~f:digest ~init:id [
      pkg.name;
      pkg.version;
      (match pkg.resolution with
       | Some resolved -> resolved
       | None -> "")
    ]
  in
  let updateWithDepId id = function
    | Dependency pkg -> digest id pkg.id
    | BuildTimeDependency pkg -> digest id pkg.id
    | DevDependency _ -> id
  in
  let id = List.fold_left ~f:updateWithDepId ~init:id dependencies in
  let hash = Digest.to_hex id in
  let hash = String.sub hash 0 8 in
  (EsyLib.Path.safeName pkg.name ^ "-" ^ EsyLib.Path.safePath pkg.version ^ "-" ^ hash)

let getenv name =
  try Some (Sys.getenv name)
  with Not_found -> None

let opamPackageName name =
  let prefix = "@opam/" in
  if Astring.String.is_prefix ~affix:prefix name
  then Astring.String.Sub.(v ~start:(String.length prefix) name |> to_string)
  else name

let addTaskBindings
  ?(useStageDirectory=false)
  ~(scopeName : [`Self | `PackageName])
  (pkg : Package.t)
  (paths : paths)
  scope
  =
  let installPath =
    if useStageDirectory
    then paths.stagePath
    else paths.installPath
  in
  let namespace = match scopeName with
  | `Self -> "self"
  | `PackageName -> pkg.name
  in
  let add key value scope =
    StringMap.add (namespace ^ "." ^ key) value scope
  in
  let addS k v s = add k (EsyCommandExpression.string v) s in
  let addB k v s = add k (EsyCommandExpression.bool v) s in
  let addP k v s = add k (EsyCommandExpression.string (Config.Value.show (Config.Path.toValue v))) s in
  scope
  |> addS "name" pkg.name
  |> addS "version" pkg.version
  |> addP "root" paths.rootPath
  |> addP "original_root" pkg.sourcePath
  |> addP "target_dir" paths.buildPath
  |> addP "install" installPath
  |> addP "bin" Config.Path.(installPath / "bin")
  |> addP "sbin" Config.Path.(installPath / "sbin")
  |> addP "lib" Config.Path.(installPath / "lib")
  |> addP "man" Config.Path.(installPath / "man")
  |> addP "doc" Config.Path.(installPath / "doc")
  |> addP "stublibs" Config.Path.(installPath / "stublibs")
  |> addP "toplevel" Config.Path.(installPath / "toplevel")
  |> addP "share" Config.Path.(installPath / "share")
  |> addP "etc" Config.Path.(installPath / "etc")
  |> addB "installed" true
  |> addS "opam:name" (opamPackageName pkg.name)
  |> addS "opam:version" pkg.version
  |> addP "opam:prefix" installPath
  |> addP "opam:bin" Config.Path.(installPath / "bin")
  |> addP "opam:etc" Config.Path.(installPath / "etc")
  |> addP "opam:doc" Config.Path.(installPath / "doc")
  |> addP "opam:man" Config.Path.(installPath / "man")
  |> addP "opam:lib" Config.Path.(installPath / "lib")
  |> addP "opam:share" Config.Path.(installPath / "share")

let addTaskEnvBindings
  (pkg : Package.t)
  (paths : paths)
  (bindings : Environment.binding list) =
  let p v = Environment.Value (Config.Value.show (Config.Path.toValue v)) in
  let open Environment in {
    name = "cur__name";
    value = Value pkg.name;
    origin = Some pkg;
  }::{
    name = "cur__version";
    value = Value pkg.version;
    origin = Some pkg;
  }::{
    name = "cur__root";
    value = p paths.rootPath;
    origin = Some pkg;
  }::{
    name = "cur__original_root";
    value = p pkg.sourcePath;
    origin = Some pkg;
  }::{
    name = "cur__target_dir";
    value = p paths.buildPath;
    origin = Some pkg;
  }::{
    name = "cur__install";
    value = p paths.stagePath;
    origin = Some pkg;
  }::{
    name = "cur__bin";
    value = p Config.Path.(paths.stagePath / "bin");
    origin = Some pkg;
  }::{
    name = "cur__sbin";
    value = p Config.Path.(paths.stagePath / "sbin");
    origin = Some pkg;
  }::{
    name = "cur__lib";
    value = p Config.Path.(paths.stagePath / "lib");
    origin = Some pkg;
  }::{
    name = "cur__man";
    value = p Config.Path.(paths.stagePath / "man");
    origin = Some pkg;
  }::{
    name = "cur__doc";
    value = p Config.Path.(paths.stagePath / "doc");
    origin = Some pkg;
  }::{
    name = "cur__stublibs";
    value = p Config.Path.(paths.stagePath / "stublibs");
    origin = Some pkg;
  }::{
    name = "cur__toplevel";
    value = p Config.Path.(paths.stagePath / "toplevel");
    origin = Some pkg;
  }::{
    name = "cur__share";
    value = p Config.Path.(paths.stagePath / "share");
    origin = Some pkg;
  }::{
    name = "cur__etc";
    value = p Config.Path.(paths.stagePath / "etc");
    origin = Some pkg;
  }::bindings

let ofPackage
    ?(includeRootDevDependenciesInEnv=false)
    ?(overrideShell=true)
    ?(forceImmutable=false)
    ?(platform=System.Platform.host)
    ?initTerm
    ?initPath
    ?initManPath
    ?initCamlLdLibraryPath
    ?finalPath
    ?finalManPath
    (rootPkg : Package.t)
  =

  let cache = Memoize.make ~size:200 () in

  let initTerm =
    let initTerm = match initTerm with
    | None -> getenv "TERM"
    | Some initTerm -> initTerm
    in Option.orDefault ~default:"" initTerm
  in

  let initPath = Option.orDefault ~default:"" initPath in
  let initManPath = Option.orDefault ~default:"" initManPath in
  let initCamlLdLibraryPath = Option.orDefault ~default:"" initCamlLdLibraryPath in

  let open Run.Syntax in

  let rec collectDependency
    ?(includeBuildTimeDependencies=true)
    (seen, dependencies)
    dep
    =
    match dep with
    | Package.Dependency depPkg
    | Package.OptDependency depPkg ->
      if Package.DependencySet.mem dep seen
      then return (seen, dependencies)
      else
        let%bind task = taskOfPackageCached ~includeSandboxEnv:true depPkg in
        let dependencies = (Dependency task)::dependencies in
        let seen = Package.DependencySet.add dep seen in
        return (seen, dependencies)
    | Package.BuildTimeDependency depPkg ->
      if Package.DependencySet.mem dep seen
      then return (seen, dependencies)
      else
        if includeBuildTimeDependencies
        then
          let%bind task = taskOfPackageCached ~includeSandboxEnv:false depPkg in
          let dependencies = (BuildTimeDependency task)::dependencies in
          let seen = Package.DependencySet.add dep seen in
          return (seen, dependencies)
        else
          return (seen, dependencies)
    | Package.DevDependency depPkg ->
      if Package.DependencySet.mem dep seen
      then return (seen, dependencies)
      else
        let%bind task = taskOfPackageCached ~includeSandboxEnv:false depPkg in
        let dependencies = (DevDependency task)::dependencies in
        let seen = Package.DependencySet.add dep seen in
        return (seen, dependencies)
    | Package.InvalidDependency { pkgName; reason; } ->
      let msg = Printf.sprintf "invalid dependency %s: %s" pkgName reason in
      Run.error msg

  and directDependenciesOf (pkg : Package.t) =
    let seen = Package.DependencySet.empty in
    let%bind _, dependencies =
      Result.List.foldLeft ~f:collectDependency ~init:(seen, []) pkg.dependencies
    in return (List.rev dependencies)

  and allDependenciesOf (pkg : Package.t) =
    let rec aux ?(includeBuildTimeDependencies=true) _pkg acc dep =
      match Package.packageOf dep with
      | None -> return acc
      | Some depPkg ->
        let%bind acc = Result.List.foldLeft
          ~f:(aux ~includeBuildTimeDependencies:false depPkg)
          ~init:acc
          depPkg.dependencies
        in
        collectDependency ~includeBuildTimeDependencies acc dep
    in
    let seen = Package.DependencySet.empty in
    let%bind _, dependencies =
      Result.List.foldLeft
        ~f:(aux ~includeBuildTimeDependencies:true pkg)
        ~init:(seen, [])
        pkg.dependencies
    in return (List.rev dependencies)

  and uniqueTasksOfDependencies dependencies =
    let f (seen, dependencies) dep =
      let task = taskOf dep in
      if StringSet.mem task.id seen
      then (seen, dependencies)
      else
        let seen = StringSet.add task.id seen in
        let dependencies = task::dependencies in
        (seen, dependencies)
    in
    let _, dependencies =
      List.fold_left ~f ~init:(StringSet.empty, []) dependencies
    in
    List.rev dependencies

  and taskOfPackage ~(includeSandboxEnv: bool) (pkg : Package.t) =

    let pkg =
      match pkg.buildType with
      | Manifest.BuildType.OutOfSource ->
        {
          pkg with
          buildEnv = {
            Manifest.Env.
            name = "DUNE_BUILD_DIR";
            value = "#{self.target_dir}";
          }::pkg.buildEnv
        }
      | _ -> pkg
    in

    let ocamlVersion =
      let f pkg = pkg.Package.name = "ocaml" in
      match Package.DependencyGraph.find ~f pkg with
      | Some pkg -> Some (toOCamlVersion pkg.version)
      | None -> None
    in

    let isRoot = pkg.id = rootPkg.id in

    let shouldIncludeDependencyInEnv = function
      | Dependency _ -> true
      | DevDependency _ -> isRoot && includeRootDevDependenciesInEnv
      | BuildTimeDependency _ -> true
    in

    let%bind allDependencies = allDependenciesOf pkg in
    let%bind dependencies = directDependenciesOf pkg in

    let allDependenciesTasks =
      allDependencies
      |> List.filter ~f:shouldIncludeDependencyInEnv
      |> uniqueTasksOfDependencies
    in
    let dependenciesTasks =
      dependencies
      |> List.filter ~f:shouldIncludeDependencyInEnv
      |> uniqueTasksOfDependencies
    in

    let id = buildId rootPkg pkg dependencies in

    let sourceType =
      match forceImmutable, pkg.sourceType with
      | true, _ -> Manifest.SourceType.Immutable
      | false, sourceType -> sourceType
    in

    let paths =
      let storePath =
        match sourceType with
        | Manifest.SourceType.Immutable -> Config.Path.store
        | Manifest.SourceType.Transient -> Config.Path.localStore
      in
      let buildPath =
        Config.Path.(storePath / Store.buildTree / id)
      in
      let buildInfoPath =
        let name = id ^ ".info" in
        Config.Path.(storePath / Store.buildTree / name)
      in
      let stagePath =
        Config.Path.(storePath / Store.stageTree / id)
      in
      let installPath =
        Config.Path.(storePath / Store.installTree / id)
      in
      let logPath =
        let basename = id ^ ".log" in
        Config.Path.(storePath / Store.buildTree / basename)
      in
      let rootPath =
        match pkg.buildType, sourceType with
        | InSource, _  -> buildPath
        | JbuilderLike, Immutable -> buildPath
        | JbuilderLike, Transient -> pkg.sourcePath
        | OutOfSource, _ -> pkg.sourcePath
        | Unsafe, Immutable  -> buildPath
        | Unsafe, _  -> pkg.sourcePath
      in {
        rootPath;
        buildPath;
        buildInfoPath;
        stagePath;
        installPath;
        logPath;
        sourcePath = pkg.sourcePath;
      }
    in

    (*
     * Scopes for #{...} syntax.
     *
     * There are two different scopes used to eval "esy.build/esy.install" and
     * "esy.exportedEnv".
     *
     * The only difference is how #{self.<path>} handled:
     * - For "esy.exportedEnv" it expands to "<store>/i/<id>/<path>"
     * - For "esy.build/esy.install" it expands to "<store>/s/<id>/<path>"
     *
     * This is because "esy.exportedEnv" is used when package is already built
     * while "esy.build/esy.install" commands are used while package is
     * building.
     *)
    let scopeForExportEnv, scopeForCommands =
      let bindings =
        StringMap.(
          empty
          |> add "opam:make" (EsyCommandExpression.string "make")
          |> add "opam:ocaml-native" (EsyCommandExpression.bool true)
          |> add "opam:ocaml-native-dynlink" (EsyCommandExpression.bool true)
          |> add "opam:jobs" (EsyCommandExpression.string "4")
          |> add "opam:pinned" (EsyCommandExpression.bool false)
        )
      in
      let bindings =
        let f bindings task =
          addTaskBindings ~scopeName:`PackageName task.pkg task.paths bindings
        in
        dependenciesTasks
        |> List.fold_left ~f ~init:bindings
      in
      let bindingsForExportedEnv =
        bindings
        |> addTaskBindings
            ~scopeName:`Self
            pkg
            paths
        |> addTaskBindings
            ~scopeName:`PackageName
            pkg
            paths
      in
      let bindingsForCommands =
        bindings
        |> addTaskBindings
            ~useStageDirectory:true
            ~scopeName:`Self
            pkg
            paths
        |> addTaskBindings
            ~useStageDirectory:true
            ~scopeName:`PackageName
            pkg
            paths
      in
      bindingsForExportedEnv, bindingsForCommands
    in

    let%bind globalEnv, localEnv =
      let f acc Manifest.ExportedEnv.{name; scope = envScope; value; exclusive = _} =
        let injectCamlLdLibraryPath, globalEnv, localEnv = acc in
        let context = Printf.sprintf "processing exportedEnv $%s" name in
        Run.withContext context (
          let%bind value =
            renderCommandExpr
              ~platform
              ~name
              ~scope:(lookupInScope scopeForExportEnv)
              value
          in
          match envScope with
          | Manifest.ExportedEnv.Global ->
            let injectCamlLdLibraryPath = name <> "CAML_LD_LIBRARY_PATH" && injectCamlLdLibraryPath in
            let globalEnv = Environment.{origin = Some pkg; name; value = Value value}::globalEnv in
            Ok (injectCamlLdLibraryPath, globalEnv, localEnv)
          | Manifest.ExportedEnv.Local ->
            let localEnv = Environment.{origin = Some pkg; name; value = Value value}::localEnv in
            Ok (injectCamlLdLibraryPath, globalEnv, localEnv)
        )
      in

      let%bind injectCamlLdLibraryPath, globalEnv, localEnv =
        Run.List.foldLeft ~f ~init:(true, [], []) pkg.exportedEnv
      in
      let%bind globalEnv = if injectCamlLdLibraryPath then
        let%bind value = renderCommandExpr
          ~platform
          ~name:"CAML_LD_LIBRARY_PATH"
          ~scope:(lookupInScope scopeForExportEnv)
          "#{self.stublibs : self.lib / 'stublibs' : $CAML_LD_LIBRARY_PATH}"
        in
        Ok (Environment.{
              name = "CAML_LD_LIBRARY_PATH";
              value = Value value;
              origin = Some pkg;
            }::globalEnv)
        else
          Ok globalEnv
      in
      return (globalEnv, localEnv)
    in

    let%bind pkgBuildEnv =
      let f {Manifest.Env. name; value;} =
        let%bind value =
          renderCommandExpr
            ~platform
            ~name
            ~scope:(lookupInScope scopeForCommands)
            value
        in
        return {
          Environment.
          name;
          value = Value value;
          origin = Some pkg;
        }
      in

      Result.List.map ~f pkg.buildEnv
    in

    let buildEnv =
      let p v = Config.(Value.show (Path.toValue v)) in

      (* All dependencies (transitive included contribute env exported to the
       * global scope (hence global)
      *)
      let globalEnvOfAllDeps =

        let getGlobalEnvForTask task =
          let path = Environment.{
            origin = Some task.pkg;
            name = "PATH";
            value =
              let value = p Config.Path.(task.paths.installPath / "bin") in
              Value (value ^ System.Environment.sep ^ "$PATH")
          }
          and manPath = Environment.{
            origin = Some task.pkg;
            name = "MAN_PATH";
            value =
              let value = p Config.Path.(task.paths.installPath / "bin") in
              Value (value ^ System.Environment.sep ^ "$MAN_PATH")
          }
          and ocamlpath = Environment.{
            origin = Some task.pkg;
            name = "OCAMLPATH";
            value =
              let value = p Config.Path.(task.paths.installPath / "lib") in
              Value (value ^ System.Environment.sep ^ "$OCAMLPATH")
          } in
          path::manPath::ocamlpath::task.globalEnv
        in
        allDependenciesTasks
        |> List.map ~f:getGlobalEnvForTask
        |> List.concat
        |> List.rev
      in

      (* Direct dependencies contribute only env exported to the local scope
      *)
      let localEnvOfDeps =
        dependenciesTasks
        |> List.map ~f:(fun task -> task.localEnv)
        |> List.concat
        |> List.rev
      in

      (* Configure environment for ocamlfind.
       * These vars can be used instead of having findlib.conf emitted.
      *)

      let ocamlfindDestdir = Environment.{
          origin = None;
          name = "OCAMLFIND_DESTDIR";
          value = Value (p Config.Path.(paths.stagePath / "lib"));
        } in

      let ocamlfindLdconf = Environment.{
          origin = None;
          name = "OCAMLFIND_LDCONF";
          value = Value "ignore";
        } in

      let ocamlfindCommands = Environment.{
          origin = None;
          name = "OCAMLFIND_COMMANDS";
          value = Value "ocamlc=ocamlc.opt ocamldep=ocamldep.opt ocamldoc=ocamldoc.opt ocamllex=ocamllex.opt ocamlopt=ocamlopt.opt";
        } in

      let initEnv = Environment.[
          {
            name = "TERM";
            value = Value initTerm;
            origin = None;
          };
          {
            name = "PATH";
            value = Value initPath;
            origin = None;
          };
          {
            name = "MAN_PATH";
            value = Value initManPath;
            origin = None;
          };
          {
            name = "CAML_LD_LIBRARY_PATH";
            value = Value initCamlLdLibraryPath;
            origin = None;
          };
        ] in

      let sandboxEnv =
        if includeSandboxEnv then
          rootPkg.sandboxEnv |> Environment.ofSandboxEnv
        else []
      in

      let finalEnv = Environment.(
          let defaultPath =
              match System.Platform.host with
              | Windows -> "$PATH;/usr/local/bin;/usr/bin;/bin;/usr/sbin;/sbin"
              | _ -> "$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
          in
          let v = [
            {
              name = "PATH";
              value = Value (Option.orDefault
                               ~default:defaultPath
                               finalPath);
              origin = None;
            };
            {
              name = "MAN_PATH";
              value = Value (Option.orDefault
                               ~default:"$MAN_PATH"
                               finalManPath);
              origin = None;
            }
          ] in
          if overrideShell then
            let shell = {
              name = "SHELL";
              value = Value "env -i /bin/bash --norc --noprofile";
              origin = None;
            } in shell::v
          else
            v
        ) in

      (finalEnv @ pkgBuildEnv @ (
          ocamlfindDestdir
          ::ocamlfindLdconf
          ::ocamlfindCommands
          ::(addTaskEnvBindings pkg paths (localEnv @ globalEnv @ localEnvOfDeps @
                                        globalEnvOfAllDeps @ sandboxEnv @ initEnv)))) |> List.rev
    in

    let%bind env =
      Run.withContext
        "evaluating environment"
        (Environment.Closed.ofBindings buildEnv)
    in

    let renderEsyCommands commands =
      CommandList.render
        ~platform
        ~env
        ~scope:(lookupInScope scopeForCommands)
        commands
    in

    let opamEnvByDependency =
      let f map (task : t) =
        match task.pkg.kind with
        | Manifest.OpamKind ->
          let open OpamVariable in
          let name = toOpamName task.pkg.name in
          let path v = string (Config.Value.show (Config.Path.toValue v)) in
          let vars = StringMap.(
            empty
            |> add "name" (string name)
            |> add "version" (string task.pkg.version)
            |> add "bin" (path Config.Path.(task.paths.installPath / "bin"))
            |> add "sbin" (path Config.Path.(task.paths.installPath / "sbin"))
            |> add "etc" (path Config.Path.(task.paths.installPath / "etc"))
            |> add "doc" (path Config.Path.(task.paths.installPath / "doc"))
            |> add "man" (path Config.Path.(task.paths.installPath / "man"))
            |> add "share" (path Config.Path.(task.paths.installPath / "share"))
            |> add "lib" (path Config.Path.(task.paths.installPath / "lib"))
            |> add "build" (path task.paths.buildPath)
          ) in
          StringMap.add name vars map
        | Manifest.EsyKind -> map
      in
      List.fold_left
        ~init:StringMap.empty
        ~f
        dependenciesTasks
    in

    let opamEnv (name : OpamVariable.Full.t) =
      let open OpamVariable in
      let var = Full.variable name in
      let scope = Full.scope name in
      let path v = string (Config.Value.show (Config.Path.toValue v)) in
      let v =
        match scope, to_string var with
        | Full.Global, "os" -> Some (string (System.Platform.show platform))
        | Full.Global, "ocaml-version" ->
          let open Option.Syntax in
          let%bind ocamlVersion = ocamlVersion in
          Some (string ocamlVersion)
        | Full.Global, "ocaml-native" -> Some (bool true)
        | Full.Global, "ocaml-native-dynlink" -> Some (bool true)
        | Full.Global, "make" -> Some (string "make")
        | Full.Global, "name" -> Some (string (toOpamName pkg.name))
        | Full.Global, "version" -> Some (string pkg.version)
        | Full.Global, "jobs" -> Some (string "4")
        | Full.Global, "prefix" -> Some (path paths.stagePath)
        | Full.Global, "bin" -> Some (path Config.Path.(paths.stagePath / "bin"))
        | Full.Global, "sbin" -> Some (path Config.Path.(paths.stagePath / "sbin"))
        | Full.Global, "etc" -> Some (path Config.Path.(paths.stagePath / "etc"))
        | Full.Global, "doc" -> Some (path Config.Path.(paths.stagePath / "doc"))
        | Full.Global, "man" -> Some (path Config.Path.(paths.stagePath / "man"))
        | Full.Global, "share" -> Some (path Config.Path.(paths.stagePath / "share"))
        | Full.Global, "lib" -> Some (path Config.Path.(paths.stagePath / "lib"))
        | Full.Global, "build" -> Some (path paths.buildPath)
        | Full.Global, "pinned" -> Some (bool false)
        | Full.Global, _ -> None
        | Full.Self, _ -> None
        | Full.Package pkg, "installed" ->
          let pkg = OpamPackage.Name.to_string pkg in
          begin match StringMap.find_opt pkg opamEnvByDependency with
          | Some _ -> Some (bool true)
          | None -> Some (bool false)
          end
        | Full.Package pkg, "enable" ->
          let pkg = OpamPackage.Name.to_string pkg in
          begin match StringMap.find_opt pkg opamEnvByDependency with
          | Some _ -> Some (string "enable")
          | None -> Some (string "disable")
          end
        | Full.Package pkg, name ->
          let open Option.Syntax in
          let pkg = OpamPackage.Name.to_string pkg in
          let%bind vars = StringMap.find_opt pkg opamEnvByDependency in
          StringMap.find_opt name vars
      in
      v
    in

    let renderOpamCommands commands =
      try return (OpamFilter.commands opamEnv commands)
      with Failure msg -> error msg
    in

    let opamSubstsToCommands substs =
      let commands =
        let f path =
          let path = Path.addExt ".in" path in
          ["substs"; Path.toString path]
        in
        List.map ~f substs
      in
      return commands
    in

    let opamPatchesToCommands patches =
      Run.withContext "processing patch field" (
        let open Run.Syntax in

        let evalFilter = function
          | path, None -> return (path, true)
          | path, Some filter ->
            let%bind filter =
              try return (OpamFilter.eval_to_bool opamEnv filter)
              with Failure msg -> error msg
            in return (path, filter)
        in

        let%bind filtered = Result.List.map ~f:evalFilter patches in

        let toCommand (path, _) =
          ["patch"; "--strip"; "1"; "--input"; Path.toString path]
        in

        return (
          filtered
          |> List.filter ~f:(fun (_, v) -> v)
          |> List.map ~f:toCommand
        )
      )
    in

    let%bind buildCommands =
      Run.withContext
        "processing esy.build"
        begin match pkg.buildCommands with
        | Manifest.EsyCommands commands ->
          let%bind commands = renderEsyCommands commands in
          let%bind applySubstsCommands = opamSubstsToCommands pkg.substs in
          let%bind applyPatchesCommands = opamPatchesToCommands pkg.patches in
          return (applySubstsCommands @ applyPatchesCommands @ commands)
        | Manifest.OpamCommands commands ->
          let%bind commands = renderOpamCommands commands in
          let%bind applySubstsCommands = opamSubstsToCommands pkg.substs in
          let%bind applyPatchesCommands = opamPatchesToCommands pkg.patches in
          return (applySubstsCommands @ applyPatchesCommands @ commands)
        end
    in

    let%bind installCommands =
      Run.withContext
        "processing esy.install"
        begin match pkg.installCommands with
        | Manifest.EsyCommands commands ->
          renderEsyCommands commands
        | Manifest.OpamCommands commands ->
          renderOpamCommands commands
        end
    in

    let task: t = {
      id;
      pkg;
      buildCommands;
      installCommands;

      env;
      globalEnv;
      localEnv;
      paths;

      sourceType;

      dependencies;

      platform = platform;
      scope = scopeForExportEnv;
    } in

    return task

  and taskOfPackageCached ~(includeSandboxEnv: bool) (pkg : Package.t) =
    let v = Memoize.compute cache pkg.id (fun _ -> taskOfPackage ~includeSandboxEnv pkg) in
    let context =
      Printf.sprintf
        "processing package: %s@%s"
        pkg.name
        pkg.version
    in
    Run.withContext context v
  in

  taskOfPackageCached ~includeSandboxEnv:true rootPkg

let buildEnv pkg =
  let open Run.Syntax in
  let%bind task = ofPackage pkg in
  Ok (Environment.Closed.bindings task.env)

let commandEnv (pkg : Package.t) =
  let open Run.Syntax in

  let%bind task =
    ofPackage
      ?finalPath:(getenv "PATH" |> Option.map ~f:(fun v -> "$PATH:" ^ v))
      ?finalManPath:(getenv "MAN_PATH"|> Option.map ~f:(fun v -> "$MAN_PATH:" ^ v))
      ~overrideShell:false
      ~includeRootDevDependenciesInEnv:true pkg
  in Ok (Environment.Closed.bindings task.env)

let sandboxEnv (pkg : Package.t) =
  let open Run.Syntax in
  let devDependencies =
    pkg.dependencies
    |> List.filter ~f:(function | Package.DevDependency _ -> true | _ -> false)
  in
  let synPkg = {
    Package.
    id = "__installation_env__";
    name = "installation_env";
    version = pkg.version;
    dependencies = (Package.Dependency pkg)::devDependencies;
    sourceType = Manifest.SourceType.Transient;
    buildType = Manifest.BuildType.OutOfSource;
    exportedEnv = [];
    buildCommands = Manifest.EsyCommands None;
    installCommands = Manifest.EsyCommands None;
    patches = [];
    substs = [];
    kind = Manifest.EsyKind;
    sandboxEnv = pkg.sandboxEnv;
    buildEnv = Manifest.Env.empty;
    sourcePath = pkg.sourcePath;
    resolution = None;
  } in
  let%bind task = ofPackage
      ?finalPath:(getenv "PATH" |> Option.map ~f:(fun v -> "$PATH:" ^ v))
      ?finalManPath:(getenv "MAN_PATH"|> Option.map ~f:(fun v -> "$MAN_PATH:" ^ v))
      ~overrideShell:false
      ~includeRootDevDependenciesInEnv:true
      synPkg
  in Ok (Environment.Closed.bindings task.env)

module DependencyGraph = DependencyGraph.Make(struct
    type t = task

    let compare = Pervasives.compare

    module Dependency = struct
      type t = task_dependency
      let compare = Pervasives.compare
    end

    let id task =
      task.id

    let traverse task =
      let f dep = match dep with
        | Dependency task
        | BuildTimeDependency task
        | DevDependency task -> (task, dep)
      in
      List.map ~f task.dependencies
  end)

let toBuildProtocol (task : task) =
  EsyBuildPackage.Task.{
    id = task.id;
    name = task.pkg.name;
    version = task.pkg.version;
    sourceType = task.sourceType;
    buildType = task.pkg.buildType;
    build = List.map ~f:(List.map ~f:EsyBuildPackage.Config.Value.v) task.buildCommands;
    install = List.map ~f:(List.map ~f:EsyBuildPackage.Config.Value.v) task.installCommands;
    sourcePath =
      EsyBuildPackage.Config.Value.v (Config.Value.show (Config.Path.toValue task.paths.sourcePath));
    env =
      task.env
      |> Environment.Closed.value
      |> Astring.String.Map.map EsyBuildPackage.Config.Value.v;
  }

let toBuildProtocolString ?(pretty=false) (task : task) =
  let task = toBuildProtocol task in
  let json = EsyBuildPackage.Task.to_yojson task in
  if pretty
  then Yojson.Safe.pretty_to_string json
  else Yojson.Safe.to_string json

(** Check if task is a root task with the current config. *)
let isRoot ~cfg task =
  let sourcePath = Config.Path.toPath cfg task.paths.sourcePath in
  Path.equal cfg.Config.sandboxPath sourcePath

let rewritePrefix ~(cfg : Config.t) ~origPrefix ~destPrefix rootPath =
  let open RunAsync.Syntax in
  let rewritePrefixInFile path =
    let cmd = Cmd.(cfg.fastreplacestringCommand % p path % p origPrefix % p destPrefix) in
    ChildProcess.run cmd
  in
  let rewriteTargetInSymlink path =
    let%bind link = Fs.readlink path in
    match Path.rem_prefix origPrefix link with
    | Some basePath ->
      let nextTargetPath = Path.(destPrefix // basePath) in
      let%bind () = Fs.unlink path in
      let%bind () = Fs.symlink ~src:nextTargetPath path in
      return ()
    | None -> return ()
  in
  let rewrite (path : Path.t) (stats : Unix.stats) =
    match stats.st_kind with
    | Unix.S_REG ->
      rewritePrefixInFile path
    | Unix.S_LNK ->
      rewriteTargetInSymlink path
    | _ -> return ()
  in
  Fs.traverse ~f:rewrite rootPath

let exportBuild ~cfg ~outputPrefixPath buildPath =
  let open RunAsync.Syntax in
  let buildId = Path.basename buildPath in
  let%lwt () = Logs_lwt.app (fun m -> m "Exporting %s" buildId) in
  let outputPath = Path.(outputPrefixPath / Printf.sprintf "%s.tar.gz" buildId) in
  let%bind origPrefix, destPrefix =
    let%bind prevStorePrefix = Fs.readFile Path.(buildPath / "_esy" / "storePrefix") in
    let nextStorePrefix = String.make (String.length prevStorePrefix) '_' in
    return (Path.v prevStorePrefix, Path.v nextStorePrefix)
  in
  let%bind stagePath =
    let path = Path.(cfg.Config.storePath / "s" / buildId) in
    let%bind () = Fs.rmPath path in
    let%bind () = Fs.copyPath ~src:buildPath ~dst:path in
    return path
  in
  let%bind () = rewritePrefix ~cfg ~origPrefix ~destPrefix stagePath in
  let%bind () = Fs.createDir (Path.parent outputPath) in
  let%bind () =
    ChildProcess.run Cmd.(
      v "tar"
      % "-C" % p (Path.parent stagePath)
      % "-cz"
      % "-f" % p outputPath
      % buildId
    )
  in
  let%lwt () = Logs_lwt.app (fun m -> m "Exporting %s: done" buildId) in
  let%bind () = Fs.rmPath stagePath in
  return ()

let importBuild (cfg : Config.t) buildPath =
  let open RunAsync.Syntax in
  let buildId, kind =
    if Path.has_ext "tar.gz" buildPath
    then
      (buildPath |> Path.rem_ext |> Path.rem_ext |> Path.basename, `Archive)
    else
      (buildPath |> Path.basename, `Dir)
  in
  let%lwt () = Logs_lwt.app (fun m -> m "Import %s" buildId) in
  let outputPath = Path.(cfg.storePath / Store.installTree / buildId) in
  if%bind Fs.exists outputPath
  then (
    let%lwt () = Logs_lwt.app (fun m -> m "Import %s: already in store, skipping..." buildId) in
    return ()
  ) else
    let importFromDir buildPath =
      let%bind origPrefix =
        let%bind v = Fs.readFile Path.(buildPath / "_esy" / "storePrefix") in
        return (Path.v v)
      in
      let%bind () = rewritePrefix ~cfg ~origPrefix ~destPrefix:cfg.storePath buildPath in
      let%bind () = Fs.rename ~src:buildPath outputPath in
      let%lwt () = Logs_lwt.app (fun m -> m "Import %s: done" buildId) in
      return ()
    in
    match kind with
    | `Dir ->
      let%bind stagePath =
        let path = Path.(cfg.Config.storePath / "s" / buildId) in
        let%bind () = Fs.rmPath path in
        let%bind () = Fs.copyPath ~src:buildPath ~dst:path in
        return path
      in
      importFromDir stagePath
    | `Archive ->
      let stagePath = Path.(cfg.storePath / Store.stageTree / buildId) in
      let%bind () =
        let cmd = Cmd.(
          v "tar"
          % "-C" % p (Path.parent stagePath)
          % "-xz"
          % "-f" % p buildPath
        ) in
        ChildProcess.run cmd
      in
      importFromDir stagePath

let isBuilt ~cfg task =
  Fs.exists Config.Path.(task.paths.installPath / "lib" |> toPath(cfg))
