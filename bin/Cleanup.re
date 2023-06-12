open EsyBuild;

let main = (projCfgs: list(ProjectConfig.t), dryRun) => {
  switch%lwt (
    {
      open RunAsync.Syntax;
      let getAllCacheEntries = globalStorePath => {
        let* allCacheEntries' =
          Fs.listDir(Path.(globalStorePath / Store.installTree));
        allCacheEntries'
        |> List.map(~f=x => Path.(globalStorePath / Store.installTree / x))
        |> RunAsync.return;
      };
      let getAllSourceEntries = prefixPath => {
        let basePath = Path.(prefixPath / "source" / "i");
        let* allCacheEntries' = Fs.listDir(basePath); /* TODO: probably use esy installsandbox to get this path */
        allCacheEntries'
        |> List.map(~f=x => Path.(basePath / x))
        |> RunAsync.return;
      };
      let mode = BuildSpec.BuildDev;
      /* projects.json is local to every esy prefix. Every project found
         there would use the same global store path. We can safely pick any
         project and get it's store path */
      let* randomProjCfg =
        try(RunAsync.return(projCfgs |> List.hd)) {
        | _ => RunAsync.error("No esy projects on this machine")
        };
      let* globalStorePath =
        randomProjCfg |> ProjectConfig.storePath |> RunAsync.ofRun;
      let* allCacheEntries = getAllCacheEntries(globalStorePath);
      let* allSourceEntries =
        getAllSourceEntries(
          ProjectConfig.globalStorePrefixPath(randomProjCfg),
        );
      let allCacheEntries =
        Path.Set.of_list @@ allCacheEntries @ allSourceEntries;
      let shortBuildPath =
        Path.(
          ProjectConfig.globalStorePrefixPath(randomProjCfg)
          / Store.version
          / Store.buildTree
        );
      let pathsToBeRemoved = [
        // staging area before installed artifacts can be installed
        Path.(globalStorePath / Store.stageTree),
        // Ex: ~/.esy/3/b - this usually contains build cache. Usually cold, and can be removed
        shortBuildPath,
        // Older versions used the longer ~/.esy/3____.../b to store build cache
        Path.(globalStorePath / Store.buildTree),
      ];
      let f = (cacheEntriesToKeep, projCfg) => {
        open Project;
        let* (project, _) = Project.make(projCfg);
        let* sourceCacheEntries =
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
        let* plan = Project.plan(mode, project);
        let* allProjectDependencies =
          BuildSandbox.Plan.all(plan)
          |> List.map(~f=task =>
               Scope.installPath(task.BuildSandbox.Task.scope)
               |> Project.renderSandboxPath(project.buildCfg)
             )
          |> RunAsync.return;

        List.iter(~f=p => print_endline(Path.show(p)), sourceCacheEntries);
        RunAsync.return(
          cacheEntriesToKeep @ allProjectDependencies @ sourceCacheEntries,
        );
      };
      let* cacheEntriesToKeep =
        RunAsync.List.foldLeft(~init=[], ~f, projCfgs);

      let buildsToBePurged = {
        let f = (acc, pathToBeRemoved) => {
          Path.Set.add(pathToBeRemoved, acc);
        };
        let init =
          cacheEntriesToKeep
          |> Path.Set.of_list
          |> Path.Set.diff(allCacheEntries);
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
        |> List.map(~f=p => LwtTaskQueue.submit(queue, () => Fs.rmPath(p)))
        |> RunAsync.List.waitAll;
      };
    }
  ) {
  | Ok () => RunAsync.return()
  | Error(e) =>
      RunAsync.ofLwt @@ Esy_logs_lwt.info(m => m("%s", Run.formatError(e)));
  };
};

