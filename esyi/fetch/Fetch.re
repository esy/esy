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
      let pkg =
        Storage.fetch(~config, ~name, ~version, ~source)
        |> RunAsync.runExn(~err="error fetching package");

      let dst = nodeModulesPath(name);

      Storage.install(~config, ~dst, pkg)
      |> RunAsync.runExn(~err="error installing package");
    },
    packagesToFetch,
  );
};
