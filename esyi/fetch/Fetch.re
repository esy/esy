module Path = EsyLib.Path;
module Config = Shared.Config;

let (/+) = Filename.concat;

let startsWith = (string, prefix) =>
  String.length(string) >= String.length(prefix)
  && String.sub(string, 0, String.length(prefix)) == prefix;

let fetch = (config: Config.t, env) => {
  open Shared.Env;
  let packagesToFetch = Hashtbl.create(100);
  let addPackage = ({name, version, source, _}) =>
    Hashtbl.replace(packagesToFetch, (name, version), source);
  env.targets
  |> List.iter(((_, {runtimeBag, _})) =>
       runtimeBag |> List.iter(addPackage)
     );
  env.buildDependencies
  |> List.iter(({package, runtimeBag}) => {
       addPackage(package);
       List.iter(addPackage, runtimeBag);
     });
  let nodeModules = Path.(config.basePath / "node_modules" |> to_string);
  /** OOh want to remove everything except for  */
  (
    /* Shared.Files.removeDeep(nodeModules); */
    if (Shared.Files.exists(nodeModules)) {
      Shared.Files.readDirectory(nodeModules)
      |> List.filter(x => ! startsWith(x, ".esy"))
      |> List.iter(x => Shared.Files.removeDeep(nodeModules /+ x));
    }
  );
  Shared.Files.mkdirp(nodeModules);
  Hashtbl.iter(
    ((name, version), source) => {
      let dest =
        Path.to_string(config.Config.packageCachePath)
        /+ FetchUtils.absname(name, version);
      FetchUtils.unpackArchive(
        dest,
        Path.to_string(config.Config.tarballCachePath),
        name,
        version,
        source,
      );
      let nmDest = nodeModules /+ name;
      if (Shared.Files.exists(nmDest)) {
        failwith("Duplicate modules");
      };
      Shared.Files.mkdirp(Filename.dirname(nmDest));
      Shared.Files.symlink(dest, nmDest);
    },
    packagesToFetch,
  );
  let resolved =
    Resolved.fromEnv(env, Path.to_string(config.Config.packageCachePath));
  Shared.Files.mkdirp(
    Path.(
      config.Config.basePath / "node_modules" / ".cache" / "_esy" |> to_string
    ),
  );
  Shared.Files.writeFile(
    Path.(
      config.Config.basePath
      / "node_modules"
      / ".cache"
      / "_esy"
      / "esy.resolved"
      |> to_string
    ),
    Yojson.Basic.pretty_to_string(resolved),
  )
  |> ignore;
};
