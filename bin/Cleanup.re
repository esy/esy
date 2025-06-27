open EsyBuild;
open RunAsync.Syntax;

/***********************************************************************/
/* Return all cached builds present at given global store path. Just a */
/* matter of returning all directory contents                          */
/***********************************************************************/

let getAllCacheEntries = globalStorePath => {
  let* allCacheEntries' =
    Fs.listDir(Path.(globalStorePath / Store.installTree));
  allCacheEntries'
  |> List.map(~f=x => Path.(globalStorePath / Store.installTree / x))
  |> RunAsync.return;
};

let getAllSourceEntries = prefixPath => {
  // TODO: EsyFetch.Config.make need not have been effectful
  // The mkdir() that is being run in the next line is unnecessary
  /* let* EsyFetch.Config.{ sourceInstallPath: basePath } = EsyFetch.Config.make(~prefixPath, ()); */
  let basePath = Path.(prefixPath / "source" / "1" / "i");
  let* allCacheEntries' = Fs.listDir(basePath); /* TODO: probably use esy installsandbox to get this path */
  allCacheEntries' |> List.map(~f=x => Path.(basePath / x)) |> RunAsync.return;
};

let main = (projCfgs: RunAsync.t(list(ProjectConfig.t)), dryRun) => {
  let* projCfgs = projCfgs;
  let* prefixPath = {
    let* prefixPathViaEsyRc =
      RunAsync.try_(
        ~catch=_ => RunAsync.return(None),
        EsyRc.ofPathOpt(Path.homePath()),
      );
    switch (prefixPathViaEsyRc) {
    | Some({EsyRc.prefixPath: Some(prefixPath), _}) =>
      RunAsync.return(prefixPath)
    | _ =>
      switch (Sys.getenv_opt("ESY__PREFIX")) {
      | Some(esyPrefixStr) =>
        switch (Path.ofString(esyPrefixStr)) {
        | Ok(prefixPath) => RunAsync.return(prefixPath)
        | e => RunAsync.ofBosError(e)
        }
      | None => Path.(Path.homePath() / ".esy") |> RunAsync.return
      }
    };
  };

  // Update projects.json to remove project paths that
  // no longer exist.
  // Cleanup.main is called after such paths have been
  // filtered out, so we just have to update the file
  // with this filtered list
  let* () =
    projCfgs
    |> List.map(~f=projectConfig => projectConfig.ProjectConfig.path)
    |> EsyFetch.ProjectList.update(prefixPath);

  switch%lwt (
    {
      let mode = BuildSpec.BuildDev;
      let* allSourceEntries = getAllSourceEntries(prefixPath);
      let f =
          (
            (allCacheEntriesSoFar, cacheEntriesToKeep, pathsToBeRemoved),
            projCfg,
          ) => {
        open Project;

        /*************************************************************************/
        /* Even within the same esy prefix, projects could have different store  */
        /* paths (ie differing in terms of number of underscores). This is       */
        /* because, each project could be supplying a different --ocaml-pkg-name */
        /* or --ocaml-version that affect the store path length                  */
        /*************************************************************************/

        let* globalStorePath =
          projCfg |> ProjectConfig.storePath |> RunAsync.ofRun;
        let* () =
          RunAsync.ofLwt @@
          Logs_lwt.debug(m =>
            m("globalStorePath %a", Path.pp, globalStorePath)
          );

        /* Unlike sources, cached builds dependent on project */
        /* configuration - prefix paths could different. */
        let* allCacheEntries = getAllCacheEntries(globalStorePath);
        let* () =
          RunAsync.ofLwt @@ Logs_lwt.debug(m => m("allCacheEntries\n"));
        let* () =
          allCacheEntries
          |> List.map(~f=entry =>
               RunAsync.ofLwt @@ Logs_lwt.debug(m => m("%a", Path.pp, entry))
             )
          |> RunAsync.List.waitAll;
        let allCacheEntriesSoFar = allCacheEntriesSoFar @ allCacheEntries;

        let pathsToBeRemoved =
          pathsToBeRemoved
          @ Path.[
              //  Old sources cache path
              ProjectConfig.globalStorePrefixPath(projCfg) / "source" / "i",
              // staging area before installed artifacts can be installed
              globalStorePath / Store.stageTree,
              // Older versions used the longer ~/.esy/4____.../b to store build cache
              globalStorePath / Store.buildTree,
            ];

        // Getting cached sources needed by the project
        let* (project, _) = Project.make(projCfg);
        let* allProjectSources =
          RunAsync.ofRun(
            {
              open Run.Syntax;
              let* solved = project.solved;
              let* {installation, _} = solved.fetched;
              installation
              |> EsyFetch.Installation.entries
              |> List.map(~f=((_, location)) => location)
              |> Run.return;
            },
          );

        // Getting cached builds needed by the project
        let* plan = Project.plan(mode, project);
        let* allProjectDependencies =
          BuildSandbox.Plan.all(plan)
          |> List.map(~f=task =>
               Scope.installPath(task.BuildSandbox.Task.scope)
               |> Project.renderSandboxPath(project.buildCfg)
             )
          |> RunAsync.return;

        let cacheEntriesToKeep =
          cacheEntriesToKeep @ allProjectDependencies @ allProjectSources;

        RunAsync.return((
          allCacheEntriesSoFar,
          cacheEntriesToKeep,
          pathsToBeRemoved,
        ));
      };

      let shortBuildPath = Path.(prefixPath / Store.version / Store.buildTree);
      let initialAllCacheEntriesSoFar = allSourceEntries;
      let initialCacheEntriesToKeep = [];
      let initialPathsToBeRemoved = [
        // Ex: ~/.esy/3/b - this usually contains build cache. Usually cold, and can be removed
        shortBuildPath,
      ];
      let* (allCacheEntriesSoFar, cacheEntriesToKeep, pathsToBeRemoved) =
        switch (projCfgs) {
        | [] =>
          RunAsync.error(
            "Empty list of projects supplied to cleanup. Cannot reliably purge cached builds",
          )
        | projCfgs =>
          RunAsync.List.foldLeft(
            ~init=(
              initialAllCacheEntriesSoFar,
              initialPathsToBeRemoved,
              initialCacheEntriesToKeep,
            ),
            ~f,
            projCfgs,
          )
        };

      let buildsToBePurged = {
        let f = (acc, pathToBeRemoved) => {
          Path.Set.add(pathToBeRemoved, acc);
        };
        let init =
          cacheEntriesToKeep
          |> Path.Set.of_list
          |> Path.Set.diff(Path.Set.of_list(allCacheEntriesSoFar));
        List.fold_left(~f, ~init, pathsToBeRemoved);
      };

      if (dryRun) {
        if (!Path.Set.is_empty(buildsToBePurged)) {
          print_endline("Will be purging the following");
          Path.Set.iter(
            p => p |> Path.show |> print_endline,
            buildsToBePurged,
          );
        } else {
          print_endline("No builds to be purged");
        };
        RunAsync.return();
      } else {
        let queue = LwtTaskQueue.create(~concurrency=40, ());
        Path.Set.elements(buildsToBePurged)
        |> List.map(~f=p =>
             LwtTaskQueue.submit(queue, ()
               /* RunAsync.try_(~catch=_ => RunAsync.return(), Fs.rmPath(p)) */
               => Fs.rmPath(p))
           )
        |> RunAsync.List.waitAll;
      };
    }
  ) {
  | Ok () => RunAsync.return()
  | Error((msg, _context)) =>
    RunAsync.ofLwt @@ Logs_lwt.app(m => m("%s", msg))
  };
};
