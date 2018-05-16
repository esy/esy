
let (/+) = Filename.concat;

let startsWith = (string, prefix) => String.length(string) >= String.length(prefix) && String.sub(string, 0, String.length(prefix)) == prefix;

let fetch = (basedir, env) => {
  open Shared.Env;
  let packagesToFetch = Hashtbl.create(100);
  let addPackage = ({name, version, source}) => Hashtbl.replace(packagesToFetch, (name, version), source);
  env.targets |> List.iter(((_, {runtimeBag})) => runtimeBag |> List.iter(addPackage));
  env.buildDependencies |> List.iter(({package, runtimeBag}) => {
    addPackage(package);
    List.iter(addPackage, runtimeBag)
  });

  let nodeModules = basedir /+ "node_modules";
  /** OOh want to remove everything except for  */
  /* Shared.Files.removeDeep(nodeModules); */
  if (Shared.Files.exists(nodeModules)) {
    Shared.Files.readDirectory(nodeModules) |> List.filter(x => !startsWith(x, ".esy")) |> List.iter(x => Shared.Files.removeDeep(nodeModules /+ x));
  };
  Shared.Files.mkdirp(nodeModules);

  let cache = nodeModules /+ ".esy-cache-archives";
  Shared.Files.mkdirp(cache);
  let modcache = nodeModules /+ ".esy-unpacked";
  Shared.Files.mkdirp(modcache);

  Hashtbl.iter(((name, version), source) => {
    let dest = modcache /+ FetchUtils.absname(name, version);
    FetchUtils.unpackArchive(dest, cache, name, version, source);
    let nmDest = nodeModules /+ name;
    if (Shared.Files.exists(nmDest)) {
      failwith("Duplicate modules")
    };
    Shared.Files.mkdirp(Filename.dirname(nmDest));
    Shared.Files.symlink(dest, nmDest);
  }, packagesToFetch);

  let resolved = Resolved.fromEnv(env, modcache);
  Shared.Files.writeFile(modcache /+ "esy.resolved", Yojson.Basic.pretty_to_string(resolved)) |> ignore;
};
