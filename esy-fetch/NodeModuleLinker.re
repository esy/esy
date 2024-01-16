open EsyPackageConfig;
open RunAsync.Syntax;

let getChildren = (~solution, ~fetchDepsSubset, ~node) => {
  let f = (pkg: Solution.pkg) => {
    switch (pkg.Package.version) {
    | Opam(_) => false
    | Npm(_)
    | Source(_) => true
    /*
        Allowing sources here would let us resolve to github urls for
        npm dependencies. Atleast in theory. TODO: test this
     */
    };
  };
  Solution.dependenciesBySpec(solution, fetchDepsSubset, node)
  |> List.filter(~f);
};

let getLocalStorePath = (projectPath, packageID) => {
  Path.(projectPath / "node_modules" / ".esy" / PackageId.show(packageID));
};

let linkPaths = (~link=false, src, dest) => {
  let* () = Fs.createDir(Path.parent(dest));
  let* () =
    if (link) {
      let* () =
        RunAsync.ofLwt @@
        Esy_logs_lwt.debug(m =>
          m("ln -s %s %s\n", Path.show(src), Path.show(dest))
        );
      Fs.symlink(~force=true, ~src, dest);
    } else {
      let* () =
        RunAsync.ofLwt @@
        Esy_logs_lwt.debug(m =>
          m("cp -R %s %s\n", Path.show(src), Path.show(dest))
        );
      Fs.copyPath(~src, ~dst=dest);
    };
  RunAsync.return();
};

// hardlink the children from local store to node_modules
let rec getPathsToLink' =
        (
          visitedMap,
          ~projectPath,
          ~solution,
          ~fetchDepsSubset,
          ~installation,
          ~rootPackageID,
          ~queue,
        ) => {
  switch (queue |> Queue.take_opt) {
  | Some((pkgID, nodeModulesPath)) =>
    let visited =
      visitedMap
      |> PackageId.Map.find_opt(pkgID)
      |> Stdlib.Option.value(~default=false);
    let* (visitedMap, queue) =
      switch (visited) {
      | false =>
        let visitedMap =
          PackageId.Map.update(pkgID, _ => Some(true), visitedMap);
        let node = Solution.getExn(solution, pkgID);
        let children = getChildren(~solution, ~fetchDepsSubset, ~node);
        let f = childNode => {
          let name = childNode.Package.name;
          let nodeModulesPath = Path.(nodeModulesPath / name / "node_modules");
          let pkgID = childNode.Package.id;
          let visited =
            visitedMap
            |> PackageId.Map.find_opt(pkgID)
            |> Stdlib.Option.value(~default=false);
          if (!visited) {
            Queue.add((pkgID, nodeModulesPath), queue);
          };
        };
        List.iter(~f, children);
        let f = childNode => {
          let pkgID = childNode.Package.id;
          let src = getLocalStorePath(projectPath, pkgID);
          let dest = Path.(nodeModulesPath / childNode.Package.name);
          linkPaths(~link=true, src, dest);
        };
        let* () = children |> List.map(~f) |> RunAsync.List.waitAll;
        RunAsync.return((visitedMap, queue));
      | true => RunAsync.return((visitedMap, queue))
      };
    getPathsToLink'(
      visitedMap,
      ~projectPath,
      ~solution,
      ~fetchDepsSubset,
      ~installation,
      ~rootPackageID,
      ~queue,
    );
  | None => RunAsync.return()
  };
};

let getPathsToLink = getPathsToLink'(PackageId.Map.empty);

let link = (~installation, ~solution, ~projectPath, ~fetchDepsSubset) => {
  let root = Solution.root(solution);
  let rootPackageID = root.Package.id;
  let nodeModulesPath = Path.(projectPath / "node_modules");
  let queue = {
    [(rootPackageID, nodeModulesPath)] |> List.to_seq |> Queue.of_seq;
  };
  let f = ((packageID, globalStorePath)) => {
    let dest = getLocalStorePath(projectPath, packageID);
    linkPaths(globalStorePath, dest);
  };
  let* () =
    installation
    |> Installation.entries
    |> List.filter(~f=((key, _)) =>
         PackageId.compare(key, rootPackageID) != 0
       )
    |> List.map(~f)
    |> RunAsync.List.waitAll;
  getPathsToLink(
    ~projectPath,
    ~solution,
    ~fetchDepsSubset,
    ~installation,
    ~rootPackageID,
    ~queue,
  );
};
