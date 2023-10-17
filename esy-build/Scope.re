open DepSpec;
open EsyPackageConfig;

module Package = EsyFetch.Package;
module SandboxPath = EsyBuildPackage.Config.Path;
module SandboxValue = EsyBuildPackage.Config.Value;
module SandboxEnvironment = EsyBuildPackage.Config.Environment;

/** Scope exported by a package. */
module PackageScope: {
  type t;

  let make:
    (
      ~id: BuildId.t,
      ~name: string,
      ~version: Version.t,
      ~sourceType: SourceType.t,
      ~sourcePath: SandboxPath.t,
      ~concurrency: int,
      BuildManifest.t
    ) =>
    t;

  let id: t => BuildId.t;
  let name: t => string;
  let version: t => Version.t;
  let sourceType: t => SourceType.t;
  let buildType: t => BuildType.t;

  let storePath: t => SandboxPath.t;
  let rootPath: t => SandboxPath.t;
  let sourcePath: t => SandboxPath.t;
  let buildPath: t => SandboxPath.t;
  let buildInfoPath: t => SandboxPath.t;
  let stagePath: t => SandboxPath.t;
  let installPath: t => SandboxPath.t;
  let logPath: t => SandboxPath.t;

  let jobs: t => int;

  let buildEnv:
    (~buildIsInProgress: bool, BuildSpec.mode, t) => list(BuildEnv.item);
  let buildEnvAuto:
    (~buildIsInProgress: bool, ~dev: bool, t) => list(BuildEnv.item);
  let exportedEnvLocal: t => list(ExportedEnv.item);
  let exportedEnvGlobal: t => list(ExportedEnv.item);

  let var:
    (~buildIsInProgress: bool, t, string) =>
    option(EsyCommandExpression.Value.t);
} = {
  type t = {
    id: BuildId.t,
    name: string,
    version: Version.t,
    sourcePath: SandboxPath.t,
    sourceType: SourceType.t,
    build: BuildManifest.t,
    exportedEnvLocal: list(ExportedEnv.item),
    exportedEnvGlobal: list(ExportedEnv.item),
    jobs: int,
  };

  let make =
      (
        ~id,
        ~name,
        ~version,
        ~sourceType,
        ~sourcePath,
        ~concurrency,
        build: BuildManifest.t,
      ) => {
    let (exportedEnvGlobal, exportedEnvLocal) = {
      open ExportedEnv;
      let (injectCamlLdLibraryPath, exportedEnvGlobal, exportedEnvLocal) = {
        let f =
            (
              _name,
              {ExportedEnv.name, scope: envScope, _} as item,
              (injectCamlLdLibraryPath, exportedEnvGlobal, exportedEnvLocal),
            ) =>
          switch (envScope) {
          | Global =>
            let injectCamlLdLibraryPath =
              name != "CAML_LD_LIBRARY_PATH" && injectCamlLdLibraryPath;

            let exportedEnvGlobal = [item, ...exportedEnvGlobal];
            (injectCamlLdLibraryPath, exportedEnvGlobal, exportedEnvLocal);
          | Local =>
            let exportedEnvLocal = [item, ...exportedEnvLocal];
            (injectCamlLdLibraryPath, exportedEnvGlobal, exportedEnvLocal);
          };

        StringMap.fold(f, build.exportedEnv, (true, [], []));
      };

      let exportedEnvGlobal =
        if (injectCamlLdLibraryPath) {
          let name = "CAML_LD_LIBRARY_PATH";
          let value = "#{self.stublibs : self.lib / 'stublibs' : $CAML_LD_LIBRARY_PATH}";
          [set(Global, name, value), ...exportedEnvGlobal];
        } else {
          exportedEnvGlobal;
        };

      let exportedEnvGlobal = {
        let path = set(Global, "PATH", "#{self.bin : $PATH}");
        let manPath = set(Global, "MAN_PATH", "#{self.man : $MAN_PATH}");
        let ocamlpath = set(Global, "OCAMLPATH", "#{self.lib : $OCAMLPATH}");
        [path, manPath, ocamlpath, ...exportedEnvGlobal];
      };

      (exportedEnvGlobal, exportedEnvLocal);
    };

    let jobs = max(concurrency / 2, 4);

    {
      id,
      name,
      version,
      sourceType,
      sourcePath,
      build,
      exportedEnvLocal,
      exportedEnvGlobal,
      jobs,
    };
  };

  let id = scope => scope.id;

  let name = scope =>
    switch (scope.build.name) {
    | Some(name) => name
    | None => scope.name
    };

  let version = scope =>
    switch (scope.build.version) {
    | Some(version) => version
    | None => scope.version
    };

  let sourceType = scope => scope.sourceType;
  let buildType = scope => scope.build.buildType;

  let sourcePath = scope => scope.sourcePath;

  let storePath = scope =>
    switch (scope.sourceType) {
    | Immutable => SandboxPath.store
    | ImmutableWithTransientDependencies
    | Transient => SandboxPath.localStore
    };

  let buildStorePath = scope =>
    switch (scope.sourceType) {
    | Immutable => SandboxPath.(globalStorePrefix / Store.version)
    | ImmutableWithTransientDependencies
    | Transient => SandboxPath.localStore
    };

  let buildPath = scope => {
    let storePath = buildStorePath(scope);
    SandboxPath.(storePath / Store.buildTree / BuildId.show(scope.id));
  };

  let buildInfoPath = scope => {
    let storePath = buildStorePath(scope);
    let name = BuildId.show(scope.id) ++ ".info";
    SandboxPath.(storePath / Store.buildTree / name);
  };

  let stagePath = scope => {
    let storePath = storePath(scope);
    switch (scope.build.buildType, scope.sourceType) {
    | (OutOfSource, Transient)
    | (OutOfSource, ImmutableWithTransientDependencies) =>
      SandboxPath.(storePath / Store.installTree / BuildId.show(scope.id))
    | _ => SandboxPath.(storePath / Store.stageTree / BuildId.show(scope.id))
    };
  };

  let installPath = scope => {
    let storePath = storePath(scope);
    SandboxPath.(storePath / Store.installTree / BuildId.show(scope.id));
  };

  let logPath = scope => {
    let storePath = buildStorePath(scope);
    let basename = BuildId.show(scope.id) ++ ".log";
    SandboxPath.(storePath / Store.buildTree / basename);
  };

  let jobs = scope => scope.jobs;

  let rootPath = scope =>
    switch (scope.build.buildType, scope.sourceType) {
    | (InSource, Immutable)
    | (InSource, ImmutableWithTransientDependencies)
    | (InSource, Transient) => buildPath(scope)

    | (JbuilderLike, Immutable)
    | (JbuilderLike, ImmutableWithTransientDependencies) => buildPath(scope)
    | (JbuilderLike, Transient) => scope.sourcePath

    | (OutOfSource, Immutable)
    | (OutOfSource, ImmutableWithTransientDependencies)
    | (OutOfSource, Transient) => scope.sourcePath

    | (Unsafe, Immutable)
    | (Unsafe, ImmutableWithTransientDependencies) => buildPath(scope)
    | (Unsafe, Transient) => scope.sourcePath
    };

  let exportedEnvLocal = scope => scope.exportedEnvLocal;
  let exportedEnvGlobal = scope => scope.exportedEnvGlobal;

  let var = (~buildIsInProgress, scope, id) => {
    let b = v => Some(EsyCommandExpression.bool(v));
    let s = v => Some(EsyCommandExpression.string(v));
    let p = v =>
      Some(
        EsyCommandExpression.string(
          SandboxValue.show(SandboxPath.toValue(v)),
        ),
      );
    let installPath =
      if (buildIsInProgress) {
        stagePath(scope);
      } else {
        installPath(scope);
      };

    switch (id) {
    | "id" => s(BuildId.show(scope.id))
    | "name" => s(name(scope))
    | "version" => s(Version.showSimple(version(scope)))
    | "root" => p(rootPath(scope))
    | "original_root" => p(sourcePath(scope))
    | "target_dir" => p(buildPath(scope))
    | "install" => p(installPath)
    | "bin" => p(SandboxPath.(installPath / "bin"))
    | "sbin" => p(SandboxPath.(installPath / "sbin"))
    | "lib" => p(SandboxPath.(installPath / "lib"))
    | "man" => p(SandboxPath.(installPath / "man"))
    | "doc" => p(SandboxPath.(installPath / "doc"))
    | "stublibs" => p(SandboxPath.(installPath / "stublibs"))
    | "toplevel" => p(SandboxPath.(installPath / "toplevel"))
    | "share" => p(SandboxPath.(installPath / "share"))
    | "etc" => p(SandboxPath.(installPath / "etc"))
    | "dev" =>
      b(
        switch (scope.sourceType) {
        | Immutable
        | ImmutableWithTransientDependencies => false
        | Transient => true
        },
      )
    | "jobs" => s(string_of_int(scope.jobs))
    | _ => None
    };
  };

  let buildEnvAuto = (~buildIsInProgress, ~dev, scope) => {
    open BuildEnv;
    let installPath =
      if (buildIsInProgress) {
        stagePath(scope);
      } else {
        installPath(scope);
      };

    let p = v => SandboxValue.show(SandboxPath.toValue(v));
    [
      set("cur__name", name(scope)),
      set("cur__version", Version.showSimple(version(scope))),
      set("cur__dev", if (dev) {"true"} else {"false"}),
      set("cur__root", p(rootPath(scope))),
      set("cur__original_root", p(sourcePath(scope))),
      set("cur__target_dir", p(buildPath(scope))),
      set("cur__install", p(installPath)),
      set("cur__bin", p(SandboxPath.(installPath / "bin"))),
      set("cur__sbin", p(SandboxPath.(installPath / "sbin"))),
      set("cur__lib", p(SandboxPath.(installPath / "lib"))),
      set("cur__man", p(SandboxPath.(installPath / "man"))),
      set("cur__doc", p(SandboxPath.(installPath / "doc"))),
      set("cur__stublibs", p(SandboxPath.(installPath / "stublibs"))),
      set("cur__toplevel", p(SandboxPath.(installPath / "toplevel"))),
      set("cur__share", p(SandboxPath.(installPath / "share"))),
      set("cur__etc", p(SandboxPath.(installPath / "etc"))),
      set("cur__jobs", string_of_int(scope.jobs)),
    ];
  };

  let buildEnv = (~buildIsInProgress, _mode, scope) => {
    open BuildEnv;
    let installPath =
      if (buildIsInProgress) {
        stagePath(scope);
      } else {
        installPath(scope);
      };

    let p = v => SandboxValue.show(SandboxPath.toValue(v));

    /* add builtins */
    let env = [
      set("OCAMLFIND_DESTDIR", p(SandboxPath.(installPath / "lib"))),
      set("OCAMLFIND_LDCONF", "ignore"),
    ];

    let env = {
      let f = (_name, item, env) => [item, ...env];
      StringMap.fold(f, scope.build.buildEnv, env);
    };

    // This makes dune build into $cur__target_dir location instead of
    // $cur__root/_build and thus implementing out of source builds.
    //
    // We do this only for packages marked as "esy.buildsInSource": false (the
    // default if absent).
    let env =
      switch (scope.build.buildType) {
      | OutOfSource => [set("DUNE_BUILD_DIR", p(buildPath(scope))), ...env]
      | InSource
      | JbuilderLike
      | Unsafe => env
      };

    // This makes dune store original source location in dune-package metadata
    // which is then used to generate .merlin files. Thus this enable merlin to
    // see original source locations when working with a set of linked packages
    // in esy.
    let env =
      switch (scope.sourceType, scope.build.buildType) {
      | (Transient, OutOfSource) => [
          set("DUNE_STORE_ORIG_SOURCE_DIR", "true"),
          ...env,
        ]
      | _ => env
      };

    env;
  };
};

type t = {
  platform: System.Platform.t,
  pkg: Package.t,
  mode: BuildSpec.mode,
  depspec: FetchDepSpec.t,
  children: PackageId.Map.t(bool),
  self: PackageScope.t,
  dependencies: list(t),
  directDependencies: StringMap.t(t),
  sandboxEnv: SandboxEnvironment.Bindings.t,
  finalEnv: SandboxEnvironment.Bindings.t,
};

let make =
    (
      ~platform,
      ~sandboxEnv,
      ~id,
      ~name,
      ~version,
      ~mode,
      ~depspec,
      ~sourceType,
      ~sourcePath,
      ~globalPathVariable,
      ~concurrency,
      pkg,
      buildManifest,
    ) => {
  let self =
    PackageScope.make(
      ~id,
      ~name,
      ~version,
      ~sourceType,
      ~sourcePath,
      ~concurrency,
      buildManifest,
    );

  {
    platform,
    sandboxEnv,
    children: PackageId.Map.empty,
    dependencies: [],
    directDependencies: StringMap.empty,
    self,
    mode,
    depspec,
    pkg,
    finalEnv: {
      let defaultPath =
        switch (platform, globalPathVariable) {
        | (Windows, Some(pathVar)) =>
          let esyGlobalPath = Sys.getenv(pathVar);
          "$PATH;" ++ esyGlobalPath;
        | (Windows, None) =>
          let windir = Sys.getenv("WINDIR") ++ "/System32";
          let windir = Path.normalizePathSepOfFilename(windir);
          "$PATH;/usr/local/bin;/usr/bin;/bin;/usr/sbin;/sbin;" ++ windir;
        | (_, Some(pathVar)) =>
          let esyGlobalPath = Sys.getenv(pathVar);
          "$PATH:" ++ esyGlobalPath;
        | (_, None) => "$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        };

      SandboxEnvironment.[
        Bindings.value("PATH", SandboxValue.v(defaultPath)),
        Bindings.value(
          "SHELL",
          SandboxValue.v("env -i /bin/bash --norc --noprofile"),
        ),
      ];
    },
  };
};

let add = (~direct, ~dep, scope) =>
  switch (direct, PackageId.Map.find_opt(dep.pkg.id, scope.children)) {
  | (direct, None) =>
    let directDependencies =
      if (direct) {
        let name = dep.pkg.name;
        StringMap.add(name, dep, scope.directDependencies);
      } else {
        scope.directDependencies;
      };

    let dependencies = [dep, ...scope.dependencies];
    let children = PackageId.Map.add(dep.pkg.id, direct, scope.children);
    {...scope, directDependencies, dependencies, children};
  | (true, Some(false)) =>
    let directDependencies = {
      let name = dep.pkg.name;
      StringMap.add(name, dep, scope.directDependencies);
    };

    let children = PackageId.Map.add(dep.pkg.id, direct, scope.children);
    {...scope, directDependencies, children};
  | (true, Some(true))
  | (false, Some(false))
  | (false, Some(true)) => scope
  };

let pkg = scope => scope.pkg;
let id = scope => PackageScope.id(scope.self);
let name = scope => PackageScope.name(scope.self);
let mode = scope => scope.mode;
let depspec = scope => scope.depspec;
let version = scope => PackageScope.version(scope.self);
let sourceType = scope => PackageScope.sourceType(scope.self);
let buildType = scope => PackageScope.buildType(scope.self);

let storePath = scope => PackageScope.storePath(scope.self);
let rootPath = scope => PackageScope.rootPath(scope.self);
let sourcePath = scope => PackageScope.sourcePath(scope.self);
let buildPath = scope => PackageScope.buildPath(scope.self);
let buildInfoPath = scope => PackageScope.buildInfoPath(scope.self);
let stagePath = scope => PackageScope.stagePath(scope.self);
let installPath = scope => PackageScope.installPath(scope.self);
let logPath = scope => PackageScope.logPath(scope.self);

let pp = (fmt, scope) =>
  Fmt.pf(fmt, "Scope %a", BuildId.pp, PackageScope.id(scope.self));

let exposeUserEnvWith = (makeBinding, name, scope) => {
  let finalEnv =
    switch (Sys.getenv(name)) {
    | exception Not_found => scope.finalEnv
    | v =>
      let binding = makeBinding(name, SandboxValue.v(v));
      [binding, ...scope.finalEnv];
    };

  {...scope, finalEnv};
};

let renderEnv = (env, name) =>
  switch (SandboxEnvironment.find(name, env)) {
  | Some(v) =>
    Result.return(EsyCommandExpression.string(SandboxValue.show(v)))
  | None => Result.return(EsyCommandExpression.string("$" ++ name))
  };

let render =
    (~env=?, ~environmentVariableName=?, ~buildIsInProgress, scope, expr) => {
  open Run.Syntax;
  let envVar = Option.map(~f=env => renderEnv(env), env);
  let pathSep =
    switch (scope.platform) {
    | System.Platform.Unknown
    | System.Platform.Darwin
    | System.Platform.Linux
    | System.Platform.Unix
    | System.Platform.Windows
    | System.Platform.Cygwin => "/"
    };

  let envSep =
    System.Environment.sep(
      ~platform=scope.platform,
      ~name=?environmentVariableName,
      (),
    );

  let lookup = ((namespace, name)) =>
    switch (namespace, name) {
    | (Some("self"), name) =>
      PackageScope.var(~buildIsInProgress, scope.self, name)
    | (Some(namespace), name) =>
      if (namespace == PackageScope.name(scope.self)) {
        PackageScope.var(~buildIsInProgress, scope.self, name);
      } else {
        switch (
          StringMap.find_opt(namespace, scope.directDependencies),
          name,
        ) {
        | (Some(_), "installed") => Some(EsyCommandExpression.bool(true))
        | (Some(scope), name) =>
          PackageScope.var(~buildIsInProgress=false, scope.self, name)
        | (None, "installed") => Some(EsyCommandExpression.bool(false))
        | (None, _) => None
        };
      }
    | (None, "os") =>
      Some(
        EsyCommandExpression.string(System.Platform.show(scope.platform)),
      )
    | (None, _) => None
    };

  let* v =
    Run.ofStringError(
      EsyCommandExpression.render(
        ~envVar?,
        ~pathSep,
        ~colon=envSep,
        ~scope=lookup,
        expr,
      ),
    );
  return(SandboxValue.v(v));
};

let makeSetBinding = (~buildIsInProgress, ~origin=?, scope, (name, value)) => {
  open Run.Syntax;
  let* value =
    Run.contextf(
      render(~buildIsInProgress, ~environmentVariableName=name, scope, value),
      "processing exportedEnv $%s",
      name,
    );

  return(SandboxEnvironment.Bindings.value(~origin?, name, value));
};
let makeUnsetBinding = (~buildIsInProgress as _, ~origin=?, _scope, name) => {
  // TODO: should log something
  Run.Syntax.(
    return(SandboxEnvironment.Bindings.remove(~origin?, name))
  );
};

let makeExportedEnvBindings = (~buildIsInProgress, ~origin=?, bindings, scope) => {
  let f = ({ExportedEnv.name, value, _}) =>
    switch (value) {
    | Set(value) =>
      makeSetBinding(~buildIsInProgress, ~origin?, scope, (name, value))
    | Unset => makeUnsetBinding(~buildIsInProgress, ~origin?, scope, name)
    };

  Result.List.map(~f, bindings);
};
let makeBuildEnvBindings = (~buildIsInProgress, ~origin=?, bindings, scope) => {
  let f = ({BuildEnv.name, value}) =>
    switch (value) {
    | Set(value) =>
      makeSetBinding(~buildIsInProgress, ~origin?, scope, (name, value))
    | Unset => makeUnsetBinding(~buildIsInProgress, ~origin?, scope, name)
    };

  Result.List.map(~f, bindings);
};

let buildEnv = (~buildIsInProgress, scope) => {
  open Run.Syntax;
  let bindings =
    PackageScope.buildEnv(~buildIsInProgress, scope.mode, scope.self);
  let* env = makeBuildEnvBindings(~buildIsInProgress, bindings, scope);
  return(env);
};

let buildEnvAuto = (~buildIsInProgress, scope) => {
  open Run.Syntax;
  let dev =
    switch (scope.pkg.source, scope.mode) {
    | (Link({kind: LinkDev, _}), BuildDev) => true
    | (Link({kind: LinkDev, _}), _) => false
    | (Link({kind: LinkRegular, _}), _)
    | (Install(_), _) => false
    };

  let bindings =
    PackageScope.buildEnvAuto(~buildIsInProgress, ~dev, scope.self);
  let* env = makeBuildEnvBindings(~buildIsInProgress, bindings, scope);
  return(env);
};

let exportedEnvGlobal = scope => {
  open Run.Syntax;
  let bindings = PackageScope.exportedEnvGlobal(scope.self);
  let origin = PackageId.show(scope.pkg.id);
  let* env =
    makeExportedEnvBindings(
      ~buildIsInProgress=false,
      ~origin,
      bindings,
      scope,
    );
  return(env);
};

let exportedEnvLocal = scope => {
  open Run.Syntax;
  let bindings = PackageScope.exportedEnvLocal(scope.self);
  let origin = PackageId.show(scope.pkg.id);
  let* env =
    makeExportedEnvBindings(
      ~buildIsInProgress=false,
      ~origin,
      bindings,
      scope,
    );
  return(env);
};

let env = (~includeBuildEnv, ~buildIsInProgress, scope) => {
  open Run.Syntax;

  let* dependenciesEnv = {
    let f = (env, dep) => {
      let name = dep.pkg.name;
      let isDirect = StringMap.mem(name, scope.directDependencies);
      if (isDirect) {
        let* g = exportedEnvGlobal(dep);
        let* l = exportedEnvLocal(dep);
        return(env @ g @ l);
      } else {
        let* g = exportedEnvGlobal(dep);
        return(env @ g);
      };
    };

    Run.List.foldLeft(~f, ~init=[], scope.dependencies);
  };

  let* buildEnv =
    if (includeBuildEnv) {
      buildEnv(~buildIsInProgress, scope);
    } else {
      return([]);
    };

  let* buildEnvAuto =
    if (includeBuildEnv) {
      buildEnvAuto(~buildIsInProgress, scope);
    } else {
      return([]);
    };

  return(
    List.rev(
      scope.finalEnv
      @ buildEnv
      @ dependenciesEnv
      @ buildEnvAuto
      @ scope.sandboxEnv,
    ),
  );
};

let toOCamlVersion = version => {
  let version = Version.showSimple(version);
  switch (String.split_on_char('.', version)) {
  | [major, minor, patch] =>
    let patch = {
      let v =
        try(int_of_string(patch)) {
        | _ => 0
        };
      if (v < 1000) {
        v;
      } else {
        v / 1000;
      };
    };

    major ++ ".0" ++ minor ++ "." ++ string_of_int(patch);
  | _ => version
  };
};

let ocamlVersion = scope => {
  open Option.Syntax;
  let f = dep =>
    switch (PackageScope.name(dep.self)) {
    | "ocaml" => true
    | _ => false
    };

  let* ocaml = List.find_opt(~f, scope.dependencies);
  return(toOCamlVersion(PackageScope.version(ocaml.self)));
};

let toOpamEnv = (~buildIsInProgress, scope: t, name: OpamVariable.Full.t) => {
  open OpamVariable;

  let ocamlVersion = ocamlVersion(scope);
  let opamArch = System.Arch.(show(host));

  let opamOs =
    switch (scope.platform) {
    | System.Platform.Darwin => "macos"
    | System.Platform.Linux => "linux"
    | System.Platform.Cygwin => "cygwin"
    | System.Platform.Windows => "win32"
    | System.Platform.Unix => "unix"
    | System.Platform.Unknown => "unknown"
    };

  let configPath = v => string(SandboxValue.show(SandboxPath.toValue(v)));

  let opamOsFamily = opamOs;
  let opamOsDistribution = opamOs;

  let opamname = (scope: PackageScope.t) => {
    let name = PackageScope.name(scope);
    switch (Astring.String.cut(~sep="@opam/", name)) {
    | Some(("", name)) => name
    | _ => name
    };
  };

  let ensurehasOpamScope = name =>
    switch (Astring.String.cut(~sep="@opam/", name)) {
    | Some(("", _)) => name
    | Some(_)
    | None => "@opam/" ++ name
    };

  let opamPackageScope =
      (~namespace=?, ~buildIsInProgress, scope: PackageScope.t, name) => {
    let opamname = opamname(scope);
    let installPath =
      if (buildIsInProgress) {
        PackageScope.stagePath(scope);
      } else {
        PackageScope.installPath(scope);
      };

    switch (namespace, name) {
    /* some specials for ocaml */
    | (Some("ocaml"), "native") => Some(bool(true))
    | (Some("ocaml"), "native-dynlink") => Some(bool(true))
    | (Some("ocaml"), "version") =>
      open Option.Syntax;
      let* ocamlVersion = ocamlVersion;
      Some(string(ocamlVersion));

    | (_, "hash") => Some(string(""))
    | (_, "name") => Some(string(opamname))
    | (_, "version") =>
      Some(string(Version.showSimple(PackageScope.version(scope))))
    | (_, "build-id") =>
      Some(string(BuildId.show(PackageScope.id(scope))))
    | (_, "dev") =>
      Some(
        bool(
          switch (PackageScope.sourceType(scope)) {
          | Immutable
          | ImmutableWithTransientDependencies => false
          | Transient => true
          },
        ),
      )
    | (_, "prefix") => Some(configPath(installPath))
    | (_, "bin") => Some(configPath(SandboxPath.(installPath / "bin")))
    | (_, "sbin") => Some(configPath(SandboxPath.(installPath / "sbin")))
    | (_, "etc") =>
      Some(configPath(SandboxPath.(installPath / "etc" / opamname)))
    | (_, "doc") =>
      Some(configPath(SandboxPath.(installPath / "doc" / opamname)))
    | (_, "man") => Some(configPath(SandboxPath.(installPath / "man")))
    | (_, "share") =>
      Some(configPath(SandboxPath.(installPath / "share" / opamname)))
    | (_, "share_root") =>
      Some(configPath(SandboxPath.(installPath / "share")))
    | (_, "stublibs") =>
      Some(configPath(SandboxPath.(installPath / "stublibs")))
    | (_, "toplevel") =>
      Some(configPath(SandboxPath.(installPath / "toplevel")))
    | (_, "lib") =>
      Some(configPath(SandboxPath.(installPath / "lib" / opamname)))
    | (_, "lib_root") => Some(configPath(SandboxPath.(installPath / "lib")))
    | (_, "libexec") =>
      Some(configPath(SandboxPath.(installPath / "lib" / opamname)))
    | (_, "libexec_root") =>
      Some(configPath(SandboxPath.(installPath / "lib")))
    | (_, "build") => Some(configPath(PackageScope.buildPath(scope)))
    | _ => None
    };
  };

  let installPath =
    if (buildIsInProgress) {
      PackageScope.stagePath(scope.self);
    } else {
      PackageScope.installPath(scope.self);
    };

  switch (Full.scope(name), to_string(Full.variable(name))) {
  | (Full.Global, "os") => Some(string(opamOs))
  | (Full.Global, "os-family") => Some(string(opamOsFamily))
  | (Full.Global, "os-distribution") => Some(string(opamOsDistribution))
  | (Full.Global, "os-version") => Some(string(""))
  | (Full.Global, "arch") => Some(string(opamArch))
  | (Full.Global, "opam-version") => Some(string("2"))
  | (Full.Global, "make") => Some(string("make"))
  | (Full.Global, "jobs") =>
    Some(string(string_of_int(PackageScope.jobs(scope.self))))
  | (Full.Global, "pinned") => Some(bool(false))
  | (Full.Global, "with-test")
  | (Full.Global, "dev") =>
    Some(
      bool(
        switch (PackageScope.sourceType(scope.self)) {
        | Immutable
        | ImmutableWithTransientDependencies => false
        | Transient => true
        },
      ),
    )
  | (Full.Global, "prefix") => Some(configPath(installPath))
  | (Full.Global, "bin") =>
    Some(configPath(SandboxPath.(installPath / "bin")))
  | (Full.Global, "sbin") =>
    Some(configPath(SandboxPath.(installPath / "sbin")))
  | (Full.Global, "etc") =>
    Some(configPath(SandboxPath.(installPath / "etc")))
  | (Full.Global, "doc") =>
    Some(configPath(SandboxPath.(installPath / "doc")))
  | (Full.Global, "man") =>
    Some(configPath(SandboxPath.(installPath / "man")))
  | (Full.Global, "share") =>
    Some(configPath(SandboxPath.(installPath / "share")))
  | (Full.Global, "stublibs") =>
    Some(configPath(SandboxPath.(installPath / "stublibs")))
  | (Full.Global, "toplevel") =>
    Some(configPath(SandboxPath.(installPath / "toplevel")))
  | (Full.Global, "lib") =>
    Some(configPath(SandboxPath.(installPath / "lib")))
  | (Full.Global, "libexec") =>
    Some(configPath(SandboxPath.(installPath / "lib")))
  | (Full.Global, "version") =>
    Some(string(Version.showSimple(PackageScope.version(scope.self))))
  | (Full.Global, "name") => Some(string(opamname(scope.self)))

  | (Full.Global, _) => None

  | (Full.Self, "enable") => Some(bool(true))
  | (Full.Self, "installed") => Some(bool(true))
  | (Full.Self, name) =>
    opamPackageScope(~buildIsInProgress, scope.self, name)

  | (Full.Package(namespace), name) =>
    let namespace =
      switch (OpamPackage.Name.to_string(namespace)) {
      | "ocaml" => "ocaml"
      | namespace => "@opam/" ++ namespace
      };

    switch (name) {
    | "installed" =>
      let installed = StringMap.mem(namespace, scope.directDependencies);
      Some(bool(installed));
    | "enabled" =>
      StringMap.mem(namespace, scope.directDependencies)
        ? Some(string("enable")) : Some(string("disable"))
    | name =>
      if (namespace == ensurehasOpamScope(scope.pkg.name)) {
        opamPackageScope(~buildIsInProgress, ~namespace, scope.self, name);
      } else {
        switch (StringMap.find_opt(namespace, scope.directDependencies)) {
        | Some(scope) =>
          opamPackageScope(
            ~buildIsInProgress=false,
            ~namespace,
            scope.self,
            name,
          )
        | None => None
        };
      }
    };
  };
};
