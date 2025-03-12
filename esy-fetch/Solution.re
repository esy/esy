open DepSpec;
open EsyPackageConfig;
open EsyPrimitives;

let traverse = pkg => PackageId.Set.elements(pkg.Package.dependencies);

let depSpecOfFetchDepsSubset = (spec, pkg) =>
  switch (pkg.Package.source) {
  | PackageSource.Link({kind: LinkDev, _}) => spec.FetchDepsSubset.dev
  | PackageSource.Link({kind: LinkRegular, _})
  | PackageSource.Install(_) => spec.FetchDepsSubset.all
  };

module Graph =
  Graph.Make({
    include Package;
    let traverse = traverse;
    let id = pkg => pkg.id;
    module Id = PackageId;
  });

let fold = Graph.fold;
let allDependenciesBFS = Graph.allDependenciesBFS;
let findBy = Graph.findBy;
let getExn = Graph.getExn;
let get = Graph.get;
let mem = Graph.mem;
let isRoot = Graph.isRoot;
let root = Graph.root;
let nodes = Graph.nodes;
let add = Graph.add;
let empty = Graph.empty;
type t = Graph.t;
type traverse = Graph.traverse;
type id = Graph.id;

type pkg = Package.t;

let resolve = (solution, self, id) =>
  switch (id) {
  | FetchDepSpec.Root => Graph.root(solution).id
  | FetchDepSpec.Self => self
  };

let eval = (solution, depspec, self) => {
  let resolve = id => resolve(solution, self, id);
  let rec eval' = expr =>
    switch (expr) {
    | FetchDepSpec.Package(id) => PackageId.Set.singleton(resolve(id))
    | FetchDepSpec.Dependencies(id) =>
      let pkg = Graph.getExn(solution, resolve(id));
      pkg.dependencies;
    | FetchDepSpec.DevDependencies(id) =>
      let pkg = Graph.getExn(solution, resolve(id));
      pkg.devDependencies;
    | FetchDepSpec.Union(a, b) => PackageId.Set.union(eval'(a), eval'(b))
    };

  eval'(depspec);
};

let rec collect' = (solution, depspec, seen, id) =>
  if (PackageId.Set.mem(id, seen)) {
    seen;
  } else {
    let f = (nextid, seen) => collect'(solution, depspec, seen, nextid);
    let seen = PackageId.Set.add(id, seen);
    let seen = PackageId.Set.fold(f, eval(solution, depspec, id), seen);
    seen;
  };

let collect = (solution, depspec, root) =>
  collect'(solution, depspec, PackageId.Set.empty, root);

let dependenciesBySpec = (solution, spec, self) => {
  let depspec = depSpecOfFetchDepsSubset(spec, self);
  let ids = eval(solution, depspec, self.id);
  let ids = PackageId.Set.elements(ids);
  List.map(~f=getExn(solution), ids);
};

let dependenciesByDepSpec = (solution, depspec, self) => {
  let ids = eval(solution, depspec, self.Package.id);
  let ids = PackageId.Set.elements(ids);
  List.map(~f=getExn(solution), ids);
};

let findByPath = (p, solution) => {
  open Option.Syntax;
  let f = (_id, pkg) =>
    switch (pkg.Package.source) {
    | Link({path, manifest: None, kind: _}) =>
      let path = DistPath.(path / "package.json");
      DistPath.compare(path, p) == 0;
    | Link({path, manifest: Some(filename), kind: _}) =>
      let path = DistPath.(path / ManifestSpec.show(filename));
      DistPath.compare(path, p) == 0;
    | _ => false
    };

  let%map (_id, pkg) = Graph.findBy(solution, f);
  pkg;
};

let findByName = (name, solution) => {
  open Option.Syntax;
  let f = (_id, pkg) => String.compare(pkg.Package.name, name) == 0;

  let%map (_id, pkg) = Graph.findBy(solution, f);
  pkg;
};

let findByNameVersion = (name, version, solution) => {
  open Option.Syntax;
  let compare = [%derive.ord: (string, Version.t)];
  let f = (_id, pkg) =>
    compare((pkg.Package.name, pkg.Package.version), (name, version)) == 0;

  let%map (_id, pkg) = Graph.findBy(solution, f);
  pkg;
};

let unPortableDependencies = (~expected, solution) => {
  open Package;
  let f = pkg => {
    let missingPlatforms =
      EsyOpamLibs.AvailablePlatforms.missing(
        ~expected,
        ~actual=pkg.available,
      );
    if (EsyOpamLibs.AvailablePlatforms.isEmpty(missingPlatforms)) {
      None;
    } else {
      Some((pkg, missingPlatforms));
    };
  };
  nodes(solution) |> List.filter_map(~f) |> RunAsync.return;
};
