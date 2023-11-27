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

let rec getPathsToCopy' =
        (
          visitedMap,
          paths,
          ~solution,
          ~fetchDepsSubset,
          ~installation,
          ~rootPackageID,
          ~queue,
        )
        : list((Path.t, Path.t)) => {
  switch (queue |> Queue.take_opt) {
  | Some((pkgID, nodeModulesPath)) =>
    let visited =
      visitedMap
      |> PackageId.Map.find_opt(pkgID)
      |> Stdlib.Option.value(~default=false);
    let (visitedMap, queue, paths) =
      switch (visited) {
      | false =>
        let name = PackageId.name(pkgID);
        let visitedMap =
          PackageId.Map.update(pkgID, _ => Some(true), visitedMap);
        let paths =
          if (PackageId.compare(rootPackageID, pkgID) == 0) {
            paths;
          } else {
            let packageSourceCachePath =
              Installation.findExn(pkgID, installation);
            [
              (packageSourceCachePath, Path.(nodeModulesPath / name)),
              ...paths,
            ];
          };
        let node = Solution.getExn(solution, pkgID);
        let children = getChildren(~solution, ~fetchDepsSubset, ~node);
        let f = childNode => {
          let nodeModulesPath =
            if (PackageId.compare(rootPackageID, pkgID) == 0) {
              Path.(nodeModulesPath / "node_modules");
            } else {
              Path.(nodeModulesPath / name / "node_modules");
            };
          Queue.add((childNode.Package.id, nodeModulesPath), queue);
        };
        List.iter(~f, children);
        (visitedMap, queue, paths);
      | true => (visitedMap, queue, paths)
      };
    getPathsToCopy'(
      visitedMap,
      paths,
      ~solution,
      ~fetchDepsSubset,
      ~installation,
      ~rootPackageID,
      ~queue,
    );

  | None => paths
  };
};

let getPathsToCopy = getPathsToCopy'(PackageId.Map.empty, []);

let link = (~installation, ~solution, ~projectPath, ~fetchDepsSubset) => {
  let root = Solution.root(solution);
  let rootPackageID = root.Package.id;
  let queue = {
    [(rootPackageID, projectPath)] |> List.to_seq |> Queue.of_seq;
  };
  let link = ((src, dest)) => {
    let* () = Fs.createDir(Path.parent(dest));
    let* () = Fs.hardlinkPath(~src, ~dst=dest);
    let* () =
      RunAsync.ofLwt @@
      Esy_logs_lwt.debug(m =>
        m("cp -R %s %s\n", Path.show(src), Path.show(dest))
      );
    RunAsync.return();
  };
  let paths =
    getPathsToCopy(
      ~solution,
      ~fetchDepsSubset,
      ~installation,
      ~rootPackageID,
      ~queue,
    );
  paths |> List.map(~f=link) |> RunAsync.List.waitAll;
};
