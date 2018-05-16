
open Shared.Env;

let taggedName = (name, version) => name ++ ":" ++ Shared.Lockfile.viewRealVersion(version);
let taggedPackage = ({name, version}) => taggedName(name, version);

let findPackage = (packages, name) => List.find(p => p.name == name, packages);

let rec depsForPackage = (package, runtimeBag) => {
  `Assoc(package.runtime |> List.map(((name, _, version)) => {
    let found = findPackage(runtimeBag, name);
    (taggedPackage(found), depsForPackage(found, runtimeBag))
  }))
};

/* let fromRootPackage = ({package, runtimeBag}) => depsForPackage */

let packagesForRoot = ({package, runtimeBag}) => [package, ...runtimeBag];

let collectPackages = env => {
  List.append(
    env.targets |> List.map(((_, root)) => packagesForRoot(root)) |> List.concat,
    env.buildDependencies |> List.map(packagesForRoot) |> List.concat
  )
};

let fromEnv = (env, modulesCache) => {
  let allPackages = collectPackages(env);
  `Assoc([
    ("sources", allPackages |> List.map(package => (taggedPackage(package), `String(Filename.concat(modulesCache, FetchUtils.absname(package.name, package.version))))) |> x => `Assoc(x)),
    ("targets", env.targets |> List.map(((target, root)) => ("hello", depsForPackage(root.package, root.runtimeBag))) |> x => `Assoc(x)),
    ("buildPackages", env.buildDependencies |> List.map(root => (taggedPackage(root.package), depsForPackage(root.package, root.runtimeBag))) |> x => `Assoc(x)),
    ("buildDependencies", allPackages |> List.map(package => (taggedPackage(package), `List(package.build |> List.map(((name, _, realVersion)) => `String(taggedName(name, realVersion)) )))) |> x => `Assoc(x)),
  ])
};
