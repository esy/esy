open EsyPackageConfig

module Package = EsyInstall.Package
module SandboxPath = EsyBuildPackage.Config.Path
module SandboxValue = EsyBuildPackage.Config.Value
module SandboxEnvironment = EsyBuildPackage.Config.Environment

(** Scope exported by a package. *)
module PackageScope : sig
  type t

  val make :
    id:BuildId.t
    -> name:string
    -> version:Version.t
    -> sourceType : SourceType.t
    -> sourcePath : SandboxPath.t
    -> BuildManifest.t
    -> t

  val id : t -> BuildId.t
  val name : t -> string
  val version : t -> Version.t
  val sourceType : t -> SourceType.t
  val buildType : t -> BuildType.t

  val storePath : t -> SandboxPath.t
  val rootPath : t -> SandboxPath.t
  val sourcePath : t -> SandboxPath.t
  val buildPath : t -> SandboxPath.t
  val buildInfoPath : t -> SandboxPath.t
  val stagePath : t -> SandboxPath.t
  val installPath : t -> SandboxPath.t
  val logPath : t -> SandboxPath.t

  val buildEnv : buildIsInProgress:bool -> BuildSpec.mode -> t -> (string * string) list
  val buildEnvAuto : buildIsInProgress:bool -> BuildSpec.mode -> t -> (string * string) list
  val exportedEnvLocal : t -> (string * string) list
  val exportedEnvGlobal : t -> (string * string) list

  val var : buildIsInProgress:bool -> t -> string -> EsyCommandExpression.Value.t option

end = struct
  type t = {
    id : BuildId.t;
    name : string;
    version : Version.t;
    sourcePath : SandboxPath.t;
    sourceType : SourceType.t;
    build : BuildManifest.t;
    exportedEnvLocal : (string * string) list;
    exportedEnvGlobal : (string * string) list;
  }

  let make
    ~id
    ~name
    ~version
    ~sourceType
    ~sourcePath
    (build : BuildManifest.t) =
    let exportedEnvGlobal, exportedEnvLocal =
      let injectCamlLdLibraryPath, exportedEnvGlobal, exportedEnvLocal =
        let f
          _name
          PackageConfig.ExportedEnv.{name; scope = envScope; value; exclusive = _}
          (injectCamlLdLibraryPath, exportedEnvGlobal, exportedEnvLocal)
          =
          match envScope with
          | Global ->
            let injectCamlLdLibraryPath =
              name <> "CAML_LD_LIBRARY_PATH" && injectCamlLdLibraryPath
            in
            let exportedEnvGlobal = (name, value)::exportedEnvGlobal in
            injectCamlLdLibraryPath, exportedEnvGlobal, exportedEnvLocal
          | Local ->
            let exportedEnvLocal = (name, value)::exportedEnvLocal in
            injectCamlLdLibraryPath, exportedEnvGlobal, exportedEnvLocal
        in
        StringMap.fold f build.exportedEnv (true, [], []) 
      in

      let exportedEnvGlobal =
        if injectCamlLdLibraryPath
        then
          let name = "CAML_LD_LIBRARY_PATH" in
          let value = "#{self.stublibs : self.lib / 'stublibs' : $CAML_LD_LIBRARY_PATH}" in
          (name, value)::exportedEnvGlobal
        else
          exportedEnvGlobal
      in

      let exportedEnvGlobal =
        let path = "PATH", "#{self.bin : $PATH}" in
        let manPath = "MAN_PATH", "#{self.man : $MAN_PATH}" in
        let ocamlpath = "OCAMLPATH", "#{self.lib : $OCAMLPATH}" in
        path::manPath::ocamlpath::exportedEnvGlobal
      in

      exportedEnvGlobal, exportedEnvLocal
    in

    {
      id;
      name;
      version;
      sourceType;
      sourcePath;
      build;
      exportedEnvLocal;
      exportedEnvGlobal;
    }

  let id scope = scope.id

  let name scope =
    match scope.build.name with
    | Some name -> name
    | None -> scope.name

  let version scope =
    match scope.build.version with
    | Some version -> version
    | None -> scope.version

  let sourceType scope = scope.sourceType
  let buildType scope = scope.build.buildType

  let sourcePath scope =
    scope.sourcePath

  let storePath scope =
    match scope.sourceType with
    | Immutable -> SandboxPath.store
    | ImmutableWithTransientDependencies | Transient -> SandboxPath.localStore

  let buildPath scope =
    let storePath = storePath scope in
    SandboxPath.(storePath / Store.buildTree / BuildId.show scope.id)

  let buildInfoPath scope =
    let storePath = storePath scope in
    let name = BuildId.show scope.id ^ ".info" in
    SandboxPath.(storePath / Store.buildTree / name)

  let stagePath scope =
    let storePath = storePath scope in
    match scope.build.buildType, scope.sourceType with
    | OutOfSource, Transient
    | OutOfSource, ImmutableWithTransientDependencies ->
      SandboxPath.(storePath / Store.installTree / BuildId.show scope.id)
    | _ ->
      SandboxPath.(storePath / Store.stageTree / BuildId.show scope.id)

  let installPath scope =
    let storePath = storePath scope in
    SandboxPath.(storePath / Store.installTree / BuildId.show scope.id)

  let logPath scope =
    let storePath = storePath scope in
    let basename = BuildId.show scope.id ^ ".log" in
    SandboxPath.(storePath / Store.buildTree / basename)

  let rootPath scope =
    match scope.build.buildType, scope.sourceType with
    | InSource, Immutable
    | InSource, ImmutableWithTransientDependencies
    | InSource, Transient  -> buildPath scope

    | JbuilderLike, Immutable
    | JbuilderLike, ImmutableWithTransientDependencies -> buildPath scope
    | JbuilderLike, Transient -> scope.sourcePath

    | OutOfSource, Immutable
    | OutOfSource, ImmutableWithTransientDependencies
    | OutOfSource, Transient -> scope.sourcePath

    | Unsafe, Immutable
    | Unsafe, ImmutableWithTransientDependencies -> buildPath scope
    | Unsafe, Transient -> scope.sourcePath

  let exportedEnvLocal scope = scope.exportedEnvLocal
  let exportedEnvGlobal scope = scope.exportedEnvGlobal

  let var ~buildIsInProgress scope id =
    let b v = Some (EsyCommandExpression.bool v) in
    let s v = Some (EsyCommandExpression.string v) in
    let p v = Some (EsyCommandExpression.string (SandboxValue.show (SandboxPath.toValue v))) in
    let installPath =
      if buildIsInProgress
      then stagePath scope
      else installPath scope
    in
    match id with
    | "id" -> s (BuildId.show scope.id)
    | "name" -> s (name scope)
    | "version" -> s (Version.showSimple (version scope))
    | "root" -> p (rootPath scope)
    | "original_root" -> p (sourcePath scope)
    | "target_dir" -> p (buildPath scope)
    | "install" -> p installPath
    | "bin" -> p SandboxPath.(installPath / "bin")
    | "sbin" -> p SandboxPath.(installPath / "sbin")
    | "lib" -> p SandboxPath.(installPath / "lib")
    | "man" -> p SandboxPath.(installPath / "man")
    | "doc" -> p SandboxPath.(installPath / "doc")
    | "stublibs" -> p SandboxPath.(installPath / "stublibs")
    | "toplevel" -> p SandboxPath.(installPath / "toplevel")
    | "share" -> p SandboxPath.(installPath / "share")
    | "etc" -> p SandboxPath.(installPath / "etc")
    | "dev" -> b (
      match scope.sourceType with
      | Immutable | ImmutableWithTransientDependencies -> false
      | Transient -> true)
    | _ -> None

  let buildEnvAuto ~buildIsInProgress mode scope =
    let installPath =
      if buildIsInProgress
      then stagePath scope
      else installPath scope
    in

    let p v = SandboxValue.show (SandboxPath.toValue v) in
    let dev =
      match mode, scope.sourceType with
      | BuildSpec.BuildDev, Transient -> "true"
      | BuildSpec.Build, Transient -> "false"
      | _, Immutable
      | _, ImmutableWithTransientDependencies -> "false"
    in
    [
      "cur__name", (name scope);
      "cur__version", (Version.showSimple (version scope));
      "cur__dev", dev;
      "cur__root", (p (rootPath scope));
      "cur__original_root", (p (sourcePath scope));
      "cur__target_dir", (p (buildPath scope));
      "cur__install", (p installPath);
      "cur__bin", (p SandboxPath.(installPath / "bin"));
      "cur__sbin", (p SandboxPath.(installPath / "sbin"));
      "cur__lib", (p SandboxPath.(installPath / "lib"));
      "cur__man", (p SandboxPath.(installPath / "man"));
      "cur__doc", (p SandboxPath.(installPath / "doc"));
      "cur__stublibs", (p SandboxPath.(installPath / "stublibs"));
      "cur__toplevel", (p SandboxPath.(installPath / "toplevel"));
      "cur__share", (p SandboxPath.(installPath / "share"));
      "cur__etc", (p SandboxPath.(installPath / "etc"));
    ]

  let buildEnv ~buildIsInProgress _mode scope =
    let installPath =
      if buildIsInProgress
      then stagePath scope
      else installPath scope
    in

    let p v = SandboxValue.show (SandboxPath.toValue v) in

    (* add builtins *)
    let env =
      [
        "OCAMLFIND_DESTDIR", (p SandboxPath.(installPath / "lib"));
        "OCAMLFIND_LDCONF", "ignore";
      ]
    in

    let env =
      let f _name {PackageConfig.Env. name; value;} env = (name, value)::env in
      StringMap.fold f scope.build.buildEnv env
    in

    let env =
      match scope.build.buildType with
      | OutOfSource -> ("DUNE_BUILD_DIR", p (buildPath scope))::env
      | _ -> env
    in

    env

end

type t = {
  platform : System.Platform.t;
  pkg : Package.t;
  mode : BuildSpec.mode;

  children : bool PackageId.Map.t;

  self : PackageScope.t;
  dependencies : t list;
  directDependencies : t StringMap.t;

  sandboxEnv : SandboxEnvironment.Bindings.t;
  finalEnv : SandboxEnvironment.Bindings.t;
}

let make
  ~platform
  ~sandboxEnv
  ~id
  ~name
  ~version
  ~mode
  ~sourceType
  ~sourcePath
  pkg
  build =
  let self =
    PackageScope.make
      ~id
      ~name
      ~version
      ~sourceType
      ~sourcePath
      build
  in
  {
    platform;
    sandboxEnv;
    children = PackageId.Map.empty;
    dependencies = [];
    directDependencies = StringMap.empty;
    self;
    mode;
    pkg;
    finalEnv = (
      let defaultPath =
          match platform with
          | Windows ->
              let windir = Sys.getenv("WINDIR") ^ "/System32" in
              let windir = Path.normalizePathSlashes windir in
              "$PATH;/usr/local/bin;/usr/bin;/bin;/usr/sbin;/sbin;" ^ windir
          | _ -> "$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      in
      SandboxEnvironment.[
        Bindings.value "PATH" (SandboxValue.v defaultPath);
        Bindings.value "SHELL" (SandboxValue.v "env -i /bin/bash --norc --noprofile");
      ]
    );
  }

let add ~direct ~dep scope =
  match direct, PackageId.Map.find_opt dep.pkg.id scope.children with
  | direct, None ->
    let directDependencies =
      if direct
      then
        let name = dep.pkg.name in
        StringMap.add name dep scope.directDependencies
      else scope.directDependencies
    in
    let dependencies = dep::scope.dependencies in
    let children = PackageId.Map.add dep.pkg.id direct scope.children in
    {scope with directDependencies; dependencies; children}
  | true, Some false ->
    let directDependencies =
      let name = dep.pkg.name in
      StringMap.add name dep scope.directDependencies
    in
    let children = PackageId.Map.add dep.pkg.id direct scope.children in
    {scope with directDependencies; children}
  | true, Some true
  | false, Some false
  | false, Some true -> scope


let pkg scope = scope.pkg
let id scope = PackageScope.id scope.self
let name scope = PackageScope.name scope.self
let version scope = PackageScope.version scope.self
let sourceType scope = PackageScope.sourceType scope.self
let buildType scope = PackageScope.buildType scope.self

let storePath scope = PackageScope.storePath scope.self
let rootPath scope = PackageScope.rootPath scope.self
let sourcePath scope = PackageScope.sourcePath scope.self
let buildPath scope = PackageScope.buildPath scope.self
let buildInfoPath scope = PackageScope.buildInfoPath scope.self
let stagePath scope = PackageScope.stagePath scope.self
let installPath scope = PackageScope.installPath scope.self
let logPath scope = PackageScope.logPath scope.self

let pp fmt scope =
  Fmt.pf fmt "Scope %a" BuildId.pp (PackageScope.id scope.self)

let exposeUserEnvWith makeBinding name scope =
  let finalEnv =
    match Sys.getenv name with
    | exception Not_found -> scope.finalEnv
    | v ->
      let binding = makeBinding name (SandboxValue.v v) in
      binding::scope.finalEnv
  in
  {scope with finalEnv}

let renderEnv env name =
  match SandboxEnvironment.find name env with
  | Some v -> Result.return (EsyCommandExpression.string (SandboxValue.show v))
  | None -> Result.return (EsyCommandExpression.string ("$" ^ name))

let render ?env ?environmentVariableName ~buildIsInProgress scope expr =
  let open Run.Syntax in
  let envVar = Option.map ~f:(fun env -> renderEnv env) env in
  let pathSep =
    match scope.platform with
    | System.Platform.Unknown
    | System.Platform.Darwin
    | System.Platform.Linux
    | System.Platform.Unix
    | System.Platform.Windows
    | System.Platform.Cygwin -> "/"
  in
  let envSep =
    System.Environment.sep ~platform:scope.platform ?name:environmentVariableName ()
  in
  let lookup (namespace, name) =
    match namespace, name with
    | Some "self", name -> PackageScope.var ~buildIsInProgress scope.self name
    | Some namespace, name ->
      if namespace = PackageScope.name scope.self
      then PackageScope.var ~buildIsInProgress scope.self name
      else
        begin match StringMap.find_opt namespace scope.directDependencies, name with
        | Some _, "installed" -> Some (EsyCommandExpression.bool true)
        | Some scope, name -> PackageScope.var ~buildIsInProgress:false scope.self name
        | None, "installed" -> Some (EsyCommandExpression.bool false)
        | None, _ -> None
        end
    | None, "os" -> Some (EsyCommandExpression.string (System.Platform.show scope.platform))
    | None, _ -> None
  in
  let%bind v = Run.ofStringError (
    EsyCommandExpression.render ?envVar ~pathSep ~colon:envSep ~scope:lookup expr
  ) in
  return (SandboxValue.v v)

let makeEnvBindings ~buildIsInProgress ?origin bindings scope =
  let open Run.Syntax in
  let f (name, value) =
    let%bind value =
      Run.contextf
        (render ~buildIsInProgress ~environmentVariableName:name scope value)
        "processing exportedEnv $%s" name
    in
    return (SandboxEnvironment.Bindings.value ?origin name value)
  in
  Result.List.map ~f bindings

let buildEnv ~buildIsInProgress scope =
  let open Run.Syntax in
  let bindings = PackageScope.buildEnv ~buildIsInProgress scope.mode scope.self in
  let%bind env = makeEnvBindings ~buildIsInProgress bindings scope in
  return env

let buildEnvAuto ~buildIsInProgress scope =
  let open Run.Syntax in
  let bindings = PackageScope.buildEnvAuto ~buildIsInProgress scope.mode scope.self in
  let%bind env = makeEnvBindings ~buildIsInProgress bindings scope in
  return env

let exportedEnvGlobal scope =
  let open Run.Syntax in
  let bindings = PackageScope.exportedEnvGlobal scope.self in
  let origin = PackageId.show scope.pkg.id in
  let%bind env = makeEnvBindings ~buildIsInProgress:false ~origin bindings scope in
  return env

let exportedEnvLocal scope =
  let open Run.Syntax in
  let bindings = PackageScope.exportedEnvLocal scope.self in
  let origin = PackageId.show scope.pkg.id in
  let%bind env = makeEnvBindings ~buildIsInProgress:false ~origin bindings scope in
  return env

let env ~includeBuildEnv ~buildIsInProgress scope =
  let open Run.Syntax in

  let%bind dependenciesEnv =
    let f env dep =
      let name = dep.pkg.name in
      let isDirect = StringMap.mem name scope.directDependencies in
      if isDirect
      then
        let%bind g = exportedEnvGlobal dep in
        let%bind l = exportedEnvLocal dep in
        return (env @ g @ l)
      else
        let%bind g = exportedEnvGlobal dep in
        return (env @ g)
    in
    Run.List.foldLeft ~f ~init:[] scope.dependencies
  in

  let%bind buildEnv =
    if includeBuildEnv
    then buildEnv ~buildIsInProgress scope
    else return []
  in

  let%bind buildEnvAuto =
    if includeBuildEnv
    then buildEnvAuto ~buildIsInProgress scope
    else return []
  in

  return (List.rev (
    scope.finalEnv
    @ buildEnv
    @ dependenciesEnv
    @ buildEnvAuto
    @ scope.sandboxEnv
  ))

let toOCamlVersion version =
  let version = Version.showSimple version in
  match String.split_on_char '.' version with
  | major::minor::patch::[] ->
    let patch =
      let v = try int_of_string patch with _ -> 0 in
      if v < 1000 then v else v / 1000
    in
    major ^ ".0" ^ minor ^ "." ^ (string_of_int patch)
  | _ -> version

let ocamlVersion scope =
  let open Option.Syntax in
  let f dep =
    match PackageScope.name dep.self with
    | "ocaml" -> true
    | _ -> false
  in
  let%bind ocaml = List.find_opt ~f scope.dependencies in
  return (toOCamlVersion (PackageScope.version ocaml.self))

let toOpamEnv ~buildIsInProgress (scope : t) (name : OpamVariable.Full.t) =
  let open OpamVariable in

  let ocamlVersion = ocamlVersion scope in
  let opamArch = System.Arch.(show host) in

  let opamOs =
    match scope.platform with
    | System.Platform.Darwin -> "macos"
    | System.Platform.Linux -> "linux"
    | System.Platform.Cygwin -> "cygwin"
    | System.Platform.Windows -> "win32"
    | System.Platform.Unix -> "unix"
    | System.Platform.Unknown -> "unknown"
  in

  let configPath v = string (SandboxValue.show (SandboxPath.toValue v)) in

  let opamOsFamily = opamOs in
  let opamOsDistribution = opamOs in

  let opamname (scope : PackageScope.t) =
    let name = PackageScope.name scope in
    match Astring.String.cut ~sep:"@opam/" name with
    | Some ("", name) -> name
    | _ -> name
  in

  let ensurehasOpamScope name =
    match Astring.String.cut ~sep:"@opam/" name with
    | Some ("", _) -> name
    | Some _
    | None -> "@opam/" ^ name
  in

  let opamPackageScope ?namespace ~buildIsInProgress (scope : PackageScope.t) name =
    let opamname = opamname scope in
    let installPath =
      if buildIsInProgress
      then PackageScope.stagePath scope
      else PackageScope.installPath scope
    in
    match namespace, name with

    (* some specials for ocaml *)
    | Some "ocaml", "native" -> Some (bool true)
    | Some "ocaml", "native-dynlink" -> Some (bool true)
    | Some "ocaml", "version" ->
      let open Option.Syntax in
      let%bind ocamlVersion = ocamlVersion in
      Some (string ocamlVersion)

    | _, "hash" -> Some (string "")
    | _, "name" -> Some (string opamname)
    | _, "version" -> Some (string (Version.showSimple (PackageScope.version scope)))
    | _, "build-id" -> Some (string (BuildId.show (PackageScope.id scope)))
    | _, "dev" -> Some (bool (
      match PackageScope.sourceType scope with
      | Immutable | ImmutableWithTransientDependencies -> false
      | Transient -> true))
    | _, "prefix" -> Some (configPath installPath)
    | _, "bin" -> Some (configPath SandboxPath.(installPath / "bin"))
    | _, "sbin" -> Some (configPath SandboxPath.(installPath / "sbin"))
    | _, "etc" -> Some (configPath SandboxPath.(installPath / "etc" / opamname))
    | _, "doc" -> Some (configPath SandboxPath.(installPath / "doc" / opamname))
    | _, "man" -> Some (configPath SandboxPath.(installPath / "man"))
    | _, "share" -> Some (configPath SandboxPath.(installPath / "share" / opamname))
    | _, "share_root" -> Some (configPath SandboxPath.(installPath / "share"))
    | _, "stublibs" -> Some (configPath SandboxPath.(installPath / "stublibs"))
    | _, "toplevel" -> Some (configPath SandboxPath.(installPath / "toplevel"))
    | _, "lib" -> Some (configPath SandboxPath.(installPath / "lib" / opamname))
    | _, "lib_root" -> Some (configPath SandboxPath.(installPath / "lib"))
    | _, "libexec" -> Some (configPath SandboxPath.(installPath / "lib" / opamname))
    | _, "libexec_root" -> Some (configPath SandboxPath.(installPath / "lib"))
    | _, "build" -> Some (configPath (PackageScope.buildPath scope))
    | _ -> None
  in

  let installPath =
    if buildIsInProgress
    then PackageScope.stagePath scope.self
    else PackageScope.installPath scope.self
  in
  match Full.scope name, to_string (Full.variable name) with
  | Full.Global, "os" -> Some (string opamOs)
  | Full.Global, "os-family" -> Some (string opamOsFamily)
  | Full.Global, "os-distribution" -> Some (string opamOsDistribution)
  | Full.Global, "os-version" -> Some (string "")
  | Full.Global, "arch" -> Some (string opamArch)
  | Full.Global, "opam-version" -> Some (string "2")
  | Full.Global, "make" -> Some (string "make")
  | Full.Global, "jobs" -> Some (string "4")
  | Full.Global, "pinned" -> Some (bool false)

  | Full.Global, "prefix" -> Some (configPath installPath)
  | Full.Global, "bin" -> Some (configPath SandboxPath.(installPath / "bin"))
  | Full.Global, "sbin" -> Some (configPath SandboxPath.(installPath / "sbin"))
  | Full.Global, "etc" -> Some (configPath SandboxPath.(installPath / "etc"))
  | Full.Global, "doc" -> Some (configPath SandboxPath.(installPath / "doc"))
  | Full.Global, "man" -> Some (configPath SandboxPath.(installPath / "man"))
  | Full.Global, "share" -> Some (configPath SandboxPath.(installPath / "share"))
  | Full.Global, "stublibs" -> Some (configPath SandboxPath.(installPath / "stublibs"))
  | Full.Global, "toplevel" -> Some (configPath SandboxPath.(installPath / "toplevel"))
  | Full.Global, "lib" -> Some (configPath SandboxPath.(installPath / "lib"))
  | Full.Global, "libexec" -> Some (configPath SandboxPath.(installPath / "lib"))
  | Full.Global, "version" -> Some (string (Version.showSimple (PackageScope.version scope.self)))
  | Full.Global, "name" -> Some (string (opamname scope.self))

  | Full.Global, _ -> None

  | Full.Self, "enable" -> Some (bool true)
  | Full.Self, "installed" -> Some (bool true)
  | Full.Self, name -> opamPackageScope ~buildIsInProgress scope.self name

  | Full.Package namespace, name ->
    let namespace =
      match OpamPackage.Name.to_string namespace with
      | "ocaml" -> "ocaml"
      | namespace -> "@opam/" ^ namespace
    in
    begin match name with
    | "installed" ->
      let installed = StringMap.mem namespace scope.directDependencies in
      Some (bool installed)
    | "enabled" ->
      begin match StringMap.mem namespace scope.directDependencies with
      | true -> Some (string "enable")
      | false -> Some (string "disable")
      end
    | name ->
      if namespace = ensurehasOpamScope scope.pkg.name
      then opamPackageScope ~buildIsInProgress ~namespace scope.self name
      else
        begin match StringMap.find_opt namespace scope.directDependencies with
        | Some scope -> opamPackageScope ~buildIsInProgress:false ~namespace scope.self name
        | None -> None
        end
    end
