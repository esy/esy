open EsyPackageConfig;

module DepSpec = {
  module Id = {
    [@deriving ord]
    type t =
      | Self
      | Root;

    let pp = fmt =>
      fun
      | Self => Fmt.unit("self", fmt, ())
      | Root => Fmt.unit("root", fmt, ());
  };

  include DepSpecAst.Make(Id);

  let root = Id.Root;
  let self = Id.Self;
};

module Spec = {
  type t = {
    all: DepSpec.t,
    dev: DepSpec.t,
  };

  let depspec = (spec, pkg) =>
    switch (pkg.Package.source) {
    | PackageSource.Link({kind: LinkDev, _}) => spec.dev
    | PackageSource.Link({kind: LinkRegular, _})
    | PackageSource.Install(_) => spec.all
    };

  let everything = {
    let all = DepSpec.(dependencies(self) + devDependencies(self));
    {all, dev: all};
  };
};

let traverse = pkg => PackageId.Set.elements(pkg.Package.dependencies);

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
  | DepSpec.Id.Root => Graph.root(solution).id
  | DepSpec.Id.Self => self
  };

let eval = (solution, depspec, self) => {
  let resolve = id => resolve(solution, self, id);
  let rec eval' = expr =>
    switch (expr) {
    | DepSpec.Package(id) => PackageId.Set.singleton(resolve(id))
    | DepSpec.Dependencies(id) =>
      let pkg = Graph.getExn(solution, resolve(id));
      pkg.dependencies;
    | DepSpec.DevDependencies(id) =>
      let pkg = Graph.getExn(solution, resolve(id));
      pkg.devDependencies;
    | [@implicit_arity] DepSpec.Union(a, b) =>
      PackageId.Set.union(eval'(a), eval'(b))
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
  let depspec = Spec.depspec(spec, self);
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
