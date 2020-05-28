open EsyBuild;
open Cmdliner;

module ProjectArg = {
  type t =
    | ByName(string)
    | ByPath(Path.t);

  let pp = fmt =>
    fun
    | ByPath(path) => Path.pp(fmt, path)
    | ByName(name) => Fmt.string(fmt, name);

  let isPathLike = v =>
    v.[0] == '.'
    || v.[0] == '/'
    || String.contains(v, '/')
    || String.contains(v, '\\');

  let parse = v =>
    Result.Syntax.(
      if (String.length(v) == 0) {
        error("empty project argument");
      } else if (isPathLike(v)) {
        return(ByPath(Path.v(v)));
      } else {
        return(ByName(v));
      }
    );

  let ofPath = p => ByPath(p);

  let conv = {
    open Cmdliner;
    let parse = v => Rresult.R.error_to_msg(~pp_error=Fmt.string, parse(v));
    Arg.conv(~docv="PROJECT", (parse, pp));
  };

  module Kind = {
    type t =
      | ProjectForced
      | Project
      | NoProject;

    let (+) = (a, b) =>
      switch (a, b) {
      | (ProjectForced, _)
      | (_, ProjectForced) => ProjectForced
      | (Project, _)
      | (_, Project) => Project
      | _ => NoProject
      };
  };

  let is_dir = path => {
    let path = Path.show(path);
    try(Sys.is_directory(path)) {
    // Might fail because of broken symlink or etc
    | Sys_error(_) => false
    };
  };

  let classifyPath = path => {
    let rec check = items =>
      switch (items) {
      | [] => Kind.NoProject
      | [name, ...rest] =>
        switch (name) {
        | ".esyproject" => ProjectForced
        | "package.json"
        | "esy.json" => Kind.(Project + check(rest))
        | "opam" =>
          let p = Path.(path / name);
          if (!is_dir(p)) {
            Kind.(Project + check(rest));
          } else {
            check(rest);
          };
        | name =>
          let p = Path.(path / name);
          if (Path.hasExt(".opam", p) && !is_dir(p)) {
            Kind.(Project + check(rest));
          } else {
            check(rest);
          };
        }
      };

    check(Array.to_list(Sys.readdir(Path.show(path))));
  };

  let checkPathByProjectName = (path, projectName) => {
    let rec check = items =>
      switch (items) {
      | [] => None
      | [name, ...rest] =>
        let p = Path.(path / name);
        if (!Path.hasExt(".json", p)) {
          check(rest);
        } else if (String.compare(name, projectName) == 0
                   || String.compare(name, projectName ++ ".json") == 0) {
          Some(p);
        } else {
          check(rest);
        };
      };
    check(Array.to_list(Sys.readdir(Path.show(path))));
  };

  let climbFrom = (currentPath, projectName) => {
    open Run.Syntax;

    let homePath = Path.homePath();

    let parentPath = path => {
      let path = Path.normalizeAndRemoveEmptySeg(path);
      let parent = Path.parent(path);
      /* do not climb further than root or home path */
      if (Path.compare(path, parent) != 0
          && Path.compare(path, homePath) != 0) {
        return(Path.parent(path));
      } else {
        errorf(
          "No esy project found (was looking from %a and up)",
          Path.ppPretty,
          currentPath,
        );
      };
    };

    let rec climb = path =>
      switch (projectName) {
      | None =>
        let kind = classifyPath(path);
        switch (kind) {
        | NoProject =>
          let%bind parent = parentPath(path);
          climb(parent);
        | Project =>
          let next = {
            let%bind parent = parentPath(path);
            climb(parent);
          };
          switch (next) {
          | Error(_) => return((kind, path))
          | Ok((Kind.Project | NoProject, _)) => return((kind, path))
          | Ok((ProjectForced, path)) => return((Kind.ProjectForced, path))
          };
        | ProjectForced => return((kind, path))
        };
      | Some(projectName) =>
        switch (checkPathByProjectName(path, projectName)) {
        | None =>
          let%bind parent = parentPath(path);
          climb(parent);
        | Some(path) => return((Kind.ProjectForced, path))
        }
      };

    let%bind (_kind, path) = climb(currentPath);
    return(path);
  };

  let resolve = (project: option(t)) => {
    open Run.Syntax;

    /* check if we can get projectPath from env */
    let project =
      switch (project) {
      | Some(_) => project
      | None =>
        let v =
          StringMap.find_opt(
            BuildSandbox.EsyIntrospectionEnv.rootPackageConfigPath,
            System.Environment.current,
          );
        switch (v) {
        | None => None
        | Some(v) => Some(ByPath(Path.v(v)))
        };
      };

    let%bind projectPath =
      switch (project) {
      | Some(ByPath(path)) => return(path)
      | Some(ByName(name)) => climbFrom(Path.currentPath(), Some(name))
      | None => climbFrom(Path.currentPath(), None)
      };

    if (Path.isAbs(projectPath)) {
      return(Path.normalize(projectPath));
    } else {
      return(Path.(normalize(currentPath() /\/ projectPath)));
    };
  };
};

[@deriving (show, to_yojson)]
type t = {
  mainprg: string,
  path: Path.t,
  esyVersion: string,
  spec: EsyInstall.SandboxSpec.t,
  prefixPath: option(Path.t),
  cacheTarballsPath: option(Path.t),
  fetchConcurrency: option(int),
  opamRepository: option(EsySolve.Config.checkoutCfg),
  esyOpamOverride: option(EsySolve.Config.checkoutCfg),
  npmRegistry: option(string),
  solveTimeout: option(float),
  skipRepositoryUpdate: bool,
  solveCudfCommand: option(Cmd.t),
};

let storePath = cfg => {
  let storePath =
    switch (cfg.prefixPath) {
    | None => EsyBuildPackage.Config.StorePathDefault
    | Some(path) => EsyBuildPackage.Config.StorePathOfPrefix(path)
    };

  let globalStorePrefix =
    switch (cfg.prefixPath) {
    | None => EsyBuildPackage.Config.storePrefixDefault
    | Some(prefixPath) => prefixPath
    };

  Run.ofBosError(
    EsyBuildPackage.Config.(configureStorePath(storePath, globalStorePrefix)),
  );
};

module FindProject = {};

let commonOptionsSection = Manpage.s_common_options;

let projectPath = {
  let doc = "Specifies esy project.";
  let env = Arg.env_var("ESY__PROJECT", ~doc);
  Arg.(
    value
    & opt(some(ProjectArg.conv), None)
    & info(["P", "project"], ~env, ~docs=commonOptionsSection, ~doc)
  );
};

let prefixPath = {
  let doc = "Specifies esy prefix path.";
  let env = Arg.env_var("ESY__PREFIX", ~doc);
  Arg.(
    value
    & opt(some(Cli.pathConv), None)
    & info(["prefix-path"], ~env, ~docs=commonOptionsSection, ~doc)
  );
};

let opamRepositoryArg = {
  let doc = "Specifies an opam repository to use.";
  let docv = "REMOTE[:LOCAL]";
  let env = Arg.env_var("ESYI__OPAM_REPOSITORY", ~doc);
  Arg.(
    value
    & opt(some(Cli.checkoutConv), None)
    & info(
        ["opam-repository"],
        ~env,
        ~doc,
        ~docv,
        ~docs=commonOptionsSection,
      )
  );
};

let esyOpamOverrideArg = {
  let doc = "Specifies an opam override repository to use.";
  let docv = "REMOTE[:LOCAL]";
  let env = Arg.env_var("ESYI__OPAM_OVERRIDE", ~doc);
  Arg.(
    value
    & opt(some(Cli.checkoutConv), None)
    & info(
        ["opam-override-repository"],
        ~env,
        ~doc,
        ~docv,
        ~docs=commonOptionsSection,
      )
  );
};

let cacheTarballsPath = {
  let doc = "Specifies tarballs cache directory.";
  Arg.(
    value
    & opt(some(Cli.pathConv), None)
    & info(["cache-tarballs-path"], ~doc, ~docs=commonOptionsSection)
  );
};

let npmRegistryArg = {
  let doc = "Specifies npm registry to use.";
  let env = Arg.env_var("NPM_CONFIG_REGISTRY", ~doc);
  Arg.(
    value
    & opt(some(string), None)
    & info(["npm-registry"], ~env, ~doc, ~docs=commonOptionsSection)
  );
};

let solveTimeoutArg = {
  let doc = "Specifies timeout for running depsolver.";
  Arg.(
    value
    & opt(some(float), None)
    & info(["solve-timeout"], ~doc, ~docs=commonOptionsSection)
  );
};

let skipRepositoryUpdateArg = {
  let doc = "Skip updating opam-repository and esy-opam-overrides repositories.";
  Arg.(
    value
    & flag
    & info(["skip-repository-update"], ~doc, ~docs=commonOptionsSection)
  );
};

let fetchConcurrencyArg = {
  let doc = "Specifies number of concurrent fetch tasks.";
  Arg.(
    value
    & opt(some(int), None)
    & info(["fetch-concurrency"], ~doc, ~docs=commonOptionsSection)
  );
};

let solveCudfCommandArg = {
  let doc = "Set command which is used for solving CUDF problems.";
  let env = Arg.env_var("ESY__SOLVE_CUDF_COMMAND", ~doc);
  Arg.(
    value
    & opt(some(Cli.cmdConv), None)
    & info(["solve-cudf-command"], ~env, ~doc, ~docs=commonOptionsSection)
  );
};

let make =
    (
      project,
      mainprg,
      prefixPath,
      cacheTarballsPath,
      fetchConcurrency,
      opamRepository,
      esyOpamOverride,
      npmRegistry,
      solveTimeout,
      skipRepositoryUpdate,
      solveCudfCommand,
    ) => {
  open RunAsync.Syntax;

  let%bind projectPath = RunAsync.ofRun(ProjectArg.resolve(project));
  let%bind spec = EsyInstall.SandboxSpec.ofPath(projectPath);

  let%bind prefixPath =
    switch (prefixPath) {
    | Some(prefixPath) => return(Some(prefixPath))
    | None =>
      let%bind rc = EsyRc.ofPath(spec.EsyInstall.SandboxSpec.path);
      return(rc.EsyRc.prefixPath);
    };

  return({
    mainprg,
    path: projectPath,
    esyVersion: EsyRuntime.version,
    spec,
    prefixPath,
    cacheTarballsPath,
    fetchConcurrency,
    opamRepository,
    esyOpamOverride,
    npmRegistry,
    solveTimeout,
    skipRepositoryUpdate,
    solveCudfCommand,
  });
};

let promiseTerm = {
  let parse =
      (
        mainprg,
        projectPath,
        prefixPath,
        cacheTarballsPath,
        fetchConcurrency,
        opamRepository,
        esyOpamOverride,
        npmRegistry,
        solveTimeout,
        skipRepositoryUpdate,
        solveCudfCommand,
        (),
      ) =>
    make(
      projectPath,
      mainprg,
      prefixPath,
      cacheTarballsPath,
      fetchConcurrency,
      opamRepository,
      esyOpamOverride,
      npmRegistry,
      solveTimeout,
      skipRepositoryUpdate,
      solveCudfCommand,
    );

  Cmdliner.Term.(
    const(parse)
    $ main_name
    $ projectPath
    $ prefixPath
    $ cacheTarballsPath
    $ fetchConcurrencyArg
    $ opamRepositoryArg
    $ esyOpamOverrideArg
    $ npmRegistryArg
    $ solveTimeoutArg
    $ skipRepositoryUpdateArg
    $ solveCudfCommandArg
    $ Cli.setupLogTerm
  );
};

let term =
  Cmdliner.Term.(ret(const(Cli.runAsyncToCmdlinerRet) $ promiseTerm));

let promiseTermForMultiplePaths = resolvedPathTerm => {
  let parse =
      (
        mainprg,
        paths,
        prefixPath,
        cacheTarballsPath,
        fetchConcurrency,
        opamRepository,
        esyOpamOverride,
        npmRegistry,
        solveTimeout,
        skipRepositoryUpdate,
        solveCudfCommand,
        (),
      ) =>
    paths
    |> List.map(~f=path =>
         make(
           Some(ProjectArg.ofPath(path)),
           mainprg,
           prefixPath,
           cacheTarballsPath,
           fetchConcurrency,
           opamRepository,
           esyOpamOverride,
           npmRegistry,
           solveTimeout,
           skipRepositoryUpdate,
           solveCudfCommand,
         )
       )
    |> RunAsync.List.joinAll;

  Cmdliner.Term.(
    const(parse)
    $ main_name
    $ Arg.(
        non_empty
        & pos_all(resolvedPathTerm, [])
        & info(
            [],
            ~docv="ROOT",
            ~doc="Project roots for which built artifacts must be kept",
          )
      )
    $ prefixPath
    $ cacheTarballsPath
    $ fetchConcurrencyArg
    $ opamRepositoryArg
    $ esyOpamOverrideArg
    $ npmRegistryArg
    $ solveTimeoutArg
    $ skipRepositoryUpdateArg
    $ solveCudfCommandArg
    $ Cli.setupLogTerm
  );
};

let multipleProjectConfigsTerm = paths =>
  Cmdliner.Term.(
    ret(
      const(Cli.runAsyncToCmdlinerRet) $ promiseTermForMultiplePaths(paths),
    )
  );
