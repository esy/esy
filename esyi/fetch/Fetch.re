module Path = EsyLib.Path;
module RunAsync = EsyLib.RunAsync;
module Config = Shared.Config;
module Solution = Shared.Solution;

let (/+) = Filename.concat;

let fetch = (config: Config.t, env: Solution.t) => {
  let packagesToFetch = Hashtbl.create(100);

  let addPackage = ({name, version, source, _}: Solution.fullPackage) =>
    Hashtbl.replace(packagesToFetch, (name, version), source);

  let nodeModules = Path.(config.basePath / "node_modules");

  let packageCachePath = (name, version) => {
    let name = FetchUtils.absname(name, version);
    let name = String.split_on_char('/', name);
    ListLabels.fold_left(
      ~f=Path.addSeg,
      ~init=config.Config.packageCachePath,
      name,
    );
  };

  let nodeModulesPath = name => {
    let name = String.split_on_char('/', name);
    ListLabels.fold_left(~f=Path.addSeg, ~init=nodeModules, name);
  };

  env.root.runtimeBag |> List.iter(addPackage);
  env.buildDependencies
  |> List.iter(({Solution.package, runtimeBag}) => {
       addPackage(package);
       List.iter(addPackage, runtimeBag);
     });
  Shared.Files.removeDeep(Path.toString(nodeModules));
  Shared.Files.mkdirp(Path.toString(nodeModules));
  Hashtbl.iter(
    ((name, version), source) => {
      let dest = packageCachePath(name, version);

      FetchUtils.unpackArchive(
        dest,
        Path.toString(config.Config.tarballCachePath),
        name,
        version,
        source,
      )
      |> RunAsync.runExn(~err="error fetching source");

      let nmDest = nodeModulesPath(name);
      if (Shared.Files.exists(Path.toString(nmDest))) {
        failwith("Duplicate modules");
      };
      Shared.Files.mkdirp(Filename.dirname(Path.toString(nmDest)));
      Shared.Files.symlink(Path.toString(dest), Path.toString(nmDest));
    },
    packagesToFetch,
  );
};
