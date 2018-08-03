(**
 * Build task.
 *)

module Store = EsyLib.Store

type paths = {
  rootPath : Config.Path.t;
  sourcePath : Config.Path.t;
  buildPath : Config.Path.t;
  buildInfoPath : Config.Path.t;
  stagePath : Config.Path.t;
  installPath : Config.Path.t;
  logPath : Config.Path.t;
} [@@deriving ord]

module PackageScope : sig
  type t = private {
    name : EsyCommandExpression.Value.t;
    version : EsyCommandExpression.Value.t;
    root : EsyCommandExpression.Value.t;
    original_root : EsyCommandExpression.Value.t;
    target_dir : EsyCommandExpression.Value.t;
    install : EsyCommandExpression.Value.t;
    bin : EsyCommandExpression.Value.t;
    sbin : EsyCommandExpression.Value.t;
    lib : EsyCommandExpression.Value.t;
    man : EsyCommandExpression.Value.t;
    doc : EsyCommandExpression.Value.t;
    stublibs : EsyCommandExpression.Value.t;
    toplevel : EsyCommandExpression.Value.t;
    share : EsyCommandExpression.Value.t;
    etc : EsyCommandExpression.Value.t;
  }

  val make : useStagePath:bool -> pkg:Package.t -> paths:paths -> unit -> t
  val compare : t -> t -> int
  val lookup : t -> string -> EsyCommandExpression.Value.t option

end = struct
  module Value = EsyCommandExpression.Value

  type t = {
    name : Value.t;
    version : Value.t;
    root : Value.t;
    original_root : Value.t;
    target_dir : Value.t;
    install : Value.t;
    bin : Value.t;
    sbin : Value.t;
    lib : Value.t;
    man : Value.t;
    doc : Value.t;
    stublibs : Value.t;
    toplevel : Value.t;
    share : Value.t;
    etc : Value.t;
  } [@@deriving ord]

  let make ~useStagePath ~(pkg : Package.t) ~(paths : paths) () =
    let s v = EsyCommandExpression.string v in
    let p v = EsyCommandExpression.string (Config.Value.show (Config.Path.toValue v)) in
    let installPath =
      if useStagePath
      then paths.stagePath
      else paths.installPath
    in
    {
      name = s pkg.name;
      version = s pkg.version;
      root = p paths.rootPath;
      original_root = p paths.sourcePath;
      target_dir = p paths.buildPath;
      install = p installPath;
      bin = p Config.Path.(installPath / "bin");
      sbin = p Config.Path.(installPath / "sbin");
      lib = p Config.Path.(installPath / "lib");
      man = p Config.Path.(installPath / "man");
      doc = p Config.Path.(installPath / "doc");
      stublibs = p Config.Path.(installPath / "stublibs");
      toplevel = p Config.Path.(installPath / "toplevel");
      share = p Config.Path.(installPath / "share");
      etc = p Config.Path.(installPath / "etc");
    }

  let lookup scope id =
    match id with
    | "name" -> Some scope.name;
    | "version" -> Some scope.version;
    | "root" -> Some scope.root;
    | "original_root" -> Some scope.original_root;
    | "target_dir" -> Some scope.target_dir;
    | "install" -> Some scope.install;
    | "bin" -> Some scope.bin;
    | "sbin" -> Some scope.sbin;
    | "lib" -> Some scope.lib;
    | "man" -> Some scope.man;
    | "doc" -> Some scope.doc;
    | "stublibs" -> Some scope.stublibs;
    | "toplevel" -> Some scope.toplevel;
    | "share" -> Some scope.share;
    | "etc" -> Some scope.etc;
    | _ -> None

end

module Scope : sig
  type t = {
    platform : System.Platform.t;
    self : PackageScope.t;
    dependencies : PackageScope.t StringMap.t;
  }

  val compare : t -> t -> int

  val toEsyCommandExpressionScope : t -> EsyCommandExpression.scope
  val toConcreteEsyCommandExpressionScope : cfg:Config.t -> t -> EsyCommandExpression.scope
  val toOpamEnv : ocamlVersion:string option -> t -> OpamFilter.env

end = struct
  module Value = EsyCommandExpression.Value

  type t = {
    platform : System.Platform.t;
    self : PackageScope.t;
    dependencies : PackageScope.t StringMap.t;
  } [@@deriving ord]

  let toEsyCommandExpressionScope scope (namespace, name) =
    match namespace, name with
    | Some "self", name -> PackageScope.lookup scope.self name
    | Some namespace, name ->
      begin match StringMap.find_opt namespace scope.dependencies, name with
      | Some _, "installed" -> Some (EsyCommandExpression.bool true)
      | Some scope, name -> PackageScope.lookup scope name
      | None, "installed" -> Some (EsyCommandExpression.bool false)
      | None, _ -> None
      end
    | None, "os" -> Some (EsyCommandExpression.string (System.Platform.show scope.platform))
    | None, _ -> None

  let toConcreteEsyCommandExpressionScope ~cfg scope id =
    match toEsyCommandExpressionScope scope id with
    | Some (Value.String v) ->
      let v = Config.Value.v v in
      let v = Config.Value.toString cfg v in
      Some (EsyCommandExpression.string v)
    | v -> v

  let toOpamEnv ~ocamlVersion (scope : t) (name : OpamVariable.Full.t) =
    let open OpamVariable in

    let toOpamName name =
      match Astring.String.cut ~sep:"@opam/" name with
      | Some ("", name) -> name
      | _ -> name
    in

    let isOpamName name =
      match Astring.String.cut ~sep:"@opam/" name with
      | Some ("", _name) -> true
      | _ -> false

    in

    let opamVarContents = function
      | EsyCommandExpression.Value.String s -> string s
      | EsyCommandExpression.Value.Bool s -> bool s
    in

    let opamPackageScope (scope : PackageScope.t) name =
      match name with
      | "prefix" -> Some (opamVarContents scope.install)
      | "bin" -> Some (opamVarContents scope.bin)
      | "sbin" -> Some (opamVarContents scope.sbin)
      | "etc" -> Some (opamVarContents scope.etc)
      | "doc" -> Some (opamVarContents scope.doc)
      | "man" -> Some (opamVarContents scope.man)
      | "share" -> Some (opamVarContents scope.share)
      | "lib" -> Some (opamVarContents scope.lib)
      | "build" -> Some (opamVarContents scope.target_dir)
      | "name" ->
        let name =
          match scope.name with
          | Value.String name -> string (toOpamName name)
          | Value.Bool v -> bool v
        in
        Some name
      | "version" -> Some (opamVarContents scope.version)
      | _ -> None
    in

    match Full.scope name, to_string (Full.variable name) with
    | Full.Global, "os" -> Some (string (System.Platform.show scope.platform))
    | Full.Global, "ocaml-version" ->
      let open Option.Syntax in
      let%bind ocamlVersion = ocamlVersion in
      Some (string ocamlVersion)

    | Full.Global, "ocaml-native" -> Some (bool true)
    | Full.Global, "ocaml-native-dynlink" -> Some (bool true)
    | Full.Global, "make" -> Some (string "make")
    | Full.Global, "jobs" -> Some (string "4")
    | Full.Global, "pinned" -> Some (bool false)
    | Full.Global, name -> opamPackageScope scope.self name

    | Full.Self, _ -> None

    | Full.Package namespace, "installed" ->
      let namespace = OpamPackage.Name.to_string namespace in
      if not (isOpamName namespace)
      then None
      else
        let installed = StringMap.mem namespace scope.dependencies in
        Some (bool installed)

    | Full.Package namespace, "enable" ->
      let namespace = OpamPackage.Name.to_string namespace in
      if not (isOpamName namespace)
      then None
      else
        begin match StringMap.mem namespace scope.dependencies with
        | true -> Some (string "enable")
        | false -> Some (string "disable")
        end

    | Full.Package namespace, name ->
      let namespace = OpamPackage.Name.to_string namespace in
      if not (isOpamName namespace)
      then None
      else begin
        match StringMap.find_opt namespace scope.dependencies with
        | Some scope -> opamPackageScope scope name
        | None -> None
      end

end

type t = {
  id : string;
  pkg : Package.t;

  buildCommands : string list list;
  installCommands : string list list;

  env : Environment.Closed.t;
  globalEnv : Environment.binding list;
  localEnv : Environment.binding list;
  paths : paths;

  sourceType : Manifest.SourceType.t;

  dependencies : dependency list;

  platform : System.Platform.t;
  scope : Scope.t;
}
[@@deriving ord]

and dependency =
  | Dependency of t
  | DevDependency of t
  | BuildTimeDependency of t
[@@deriving (show, eq, ord)]

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
    [@@deriving (show, eq)]

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

type task = t
type task_dependency = dependency

let renderExpression ~cfg ~task expr =
  let scope = Scope.toConcreteEsyCommandExpressionScope ~cfg task.scope in
  renderCommandExpr ~platform:task.platform ~scope expr

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

  let hashCommands (commands : Manifest.Build.commands) =
    match commands with
    | Manifest.Build.EsyCommands commands ->
      Manifest.CommandList.show commands
    | Manifest.Build.OpamCommands commands ->
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
      hashCommands pkg.build.buildCommands;
      hashCommands pkg.build.installCommands;
      patchesToString pkg.build.patches;
      Manifest.BuildType.show pkg.build.buildType;
      Manifest.Env.show pkg.build.buildEnv;
      Manifest.Env.show rootPkg.build.sandboxEnv;
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
      match pkg.build.buildType with
      | Manifest.BuildType.OutOfSource ->
        {
          pkg with
          build = {
            pkg.build with
            buildEnv = {
              Manifest.Env.
              name = "DUNE_BUILD_DIR";
              value = "#{self.target_dir}";
            }::pkg.build.buildEnv
          };
        }
      | _ -> pkg
    in

    let ocamlVersion =
      let f pkg = pkg.Package.name = "ocaml" in
      match Package.Graph.find ~f pkg with
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
      match forceImmutable, pkg.build.sourceType with
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
        match pkg.build.buildType, sourceType with
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
    let exportedScope, buildScope =

      let dependencies =
        let f map (task : t) =
          let scope =
            PackageScope.make
              ~useStagePath:false
              ~pkg:task.pkg
              ~paths:task.paths
              ()
          in
          StringMap.add task.pkg.name scope map
        in
        List.fold_left ~f ~init:StringMap.empty dependenciesTasks
      in

      let buildScope =
        let self = PackageScope.make ~useStagePath:true ~pkg ~paths () in
        {
          Scope.
          platform;
          self;
          dependencies = StringMap.add pkg.name self dependencies;
        }
      in

      let exportedScope =
        let self = PackageScope.make ~useStagePath:false ~pkg ~paths () in
        {
          Scope.
          platform;
          self;
          dependencies = StringMap.add pkg.name self dependencies;
        }
      in

      exportedScope, buildScope
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
              ~scope:(Scope.toEsyCommandExpressionScope exportedScope)
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
        Run.List.foldLeft ~f ~init:(true, [], []) pkg.build.exportedEnv
      in
      let%bind globalEnv = if injectCamlLdLibraryPath then
        let%bind value = renderCommandExpr
          ~platform
          ~name:"CAML_LD_LIBRARY_PATH"
          ~scope:(Scope.toEsyCommandExpressionScope exportedScope)
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
            ~scope:(Scope.toEsyCommandExpressionScope buildScope)
            value
        in
        return {
          Environment.
          name;
          value = Value value;
          origin = Some pkg;
        }
      in

      Result.List.map ~f pkg.build.buildEnv
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
          rootPkg.build.sandboxEnv |> Environment.ofSandboxEnv
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
        ~scope:(Scope.toEsyCommandExpressionScope buildScope)
        commands
    in

    let opamEnv = Scope.toOpamEnv ~ocamlVersion buildScope in

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
        begin match pkg.build.buildCommands with
        | Manifest.Build.EsyCommands commands ->
          let%bind commands = renderEsyCommands commands in
          let%bind applySubstsCommands = opamSubstsToCommands pkg.build.substs in
          let%bind applyPatchesCommands = opamPatchesToCommands pkg.build.patches in
          return (applySubstsCommands @ applyPatchesCommands @ commands)
        | Manifest.Build.OpamCommands commands ->
          let%bind commands = renderOpamCommands commands in
          let%bind applySubstsCommands = opamSubstsToCommands pkg.build.substs in
          let%bind applyPatchesCommands = opamPatchesToCommands pkg.build.patches in
          return (applySubstsCommands @ applyPatchesCommands @ commands)
        end
    in

    let%bind installCommands =
      Run.withContext
        "processing esy.install"
        begin match pkg.build.installCommands with
        | Manifest.Build.EsyCommands commands ->
          renderEsyCommands commands
        | Manifest.Build.OpamCommands commands ->
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
      scope = exportedScope;
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
    build = {
      Manifest.Build.
      sourceType = Manifest.SourceType.Transient;
      buildType = Manifest.BuildType.OutOfSource;
      exportedEnv = [];
      buildCommands = Manifest.Build.EsyCommands None;
      installCommands = Manifest.Build.EsyCommands None;
      patches = [];
      substs = [];
      sandboxEnv = pkg.build.sandboxEnv;
      buildEnv = Manifest.Env.empty;
    };
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

module Graph = DependencyGraph.Make(struct
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
    buildType = task.pkg.build.buildType;
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
