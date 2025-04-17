open RunAsync.Syntax;

let installPkg = (~installation, ~nodeModulesPath, pkg) => {
  let* () =
    RunAsync.ofLwt @@
    Logs_lwt.debug(m => m("NodeModuleLinker: installing %a", Package.pp, pkg));
  let pkgID = pkg.Package.id;
  let src = Installation.findExn(pkgID, installation);
  let dst = Path.(nodeModulesPath / pkg.Package.name);
  Fs.hardlinkPath(~src, ~dst);
};

module Data = {
  include Package;
  let sameVersion = (a, b) =>
    EsyPackageConfig.Version.compare(a.version, b.version);
};

module HoistingAlgorithm =
  HoistingAlgorithm.Make(Data, HoistedNodeModulesGraph);

let _debug = (~node) => HoistedNodeModulesGraph.nodePp(node);

let _debugHoist = (~node, ~lineage) =>
  if (List.length(lineage) > 0) {
    print_endline(
      Format.asprintf(
        "Node %a will be hoisted to %a",
        Package.pp,
        node.SolutionGraph.data,
        SolutionGraph.parentsPp,
        lineage,
      ),
    );
  } else {
    print_endline(
      Format.asprintf(
        "Node %a will be hoisted to <root>",
        Package.pp,
        node.SolutionGraph.data,
      ),
    );
  };

module SolutionGraphLineage = Lineage.Make(SolutionGraph);
let rec iterateSolution = (~traverse, ~hoistedGraph, iterableSolution) => {
  switch (SolutionGraph.take(~traverse, iterableSolution)) {
  | Some((node, nextIterable)) =>
    let SolutionGraph.{data, parent} = node;
    let nodeModuleEntry =
      HoistedNodeModulesGraph.makeNode(~data, ~parent=None);
    let hoistedGraph =
      switch (parent) {
      | Some(_parent) =>
        let lineage =
          node
          |> SolutionGraphLineage.constructLineage
          |> List.map(~f=solutionGraphNode =>
               solutionGraphNode.SolutionGraph.data
             );
        HoistingAlgorithm.hoistLineage(
          ~lineage,
          ~hoistedGraph,
          nodeModuleEntry,
        );
      | None =>
        Ok(
          HoistedNodeModulesGraph.addRoot(
            ~node=nodeModuleEntry,
            hoistedGraph,
          ),
        )
      };
    Stdlib.Result.bind(hoistedGraph, hoistedGraph =>
      iterateSolution(~traverse, ~hoistedGraph, nextIterable)
    );
  | None => Ok(hoistedGraph)
  };
};

module NodeModuleLineage = Lineage.Make(HoistedNodeModulesGraph);
let rec nodeModulesPathFromParent = (~baseNodeModulesPath, parent) => {
  switch (HoistedNodeModulesGraph.parent(parent)) {
  | Some(_grandparent) =>
    let lineage = NodeModuleLineage.constructLineage(parent); // This lineage is a list starting from oldest ancestor
    let lineage = List.tl(lineage); // skip root which is just parent id
    let init = baseNodeModulesPath;
    let f = (acc, node) => {
      Path.(
        acc
        / NodeModule.name(node.HoistedNodeModulesGraph.data)
        / "node_modules"
      );
    };
    List.fold_left(lineage, ~f, ~init);
  | None => /* most likely case. ie all pkgs are directly under root  */ baseNodeModulesPath
  };
};

let rec iterateHoistedNodeModulesGraph = (~f, ~init, iterableGraph) => {
  switch (HoistedNodeModulesGraph.take(iterableGraph)) {
  | Some((node, nextIterable)) =>
    let init = f(init, node);
    iterateHoistedNodeModulesGraph(~f, ~init, nextIterable);
  | None => init
  };
};

let link =
    (~sandbox, ~installation, ~projectPath, ~fetchDepsSubset, ~solution) => {
  let (report, finish) =
    Cli.createProgressReporter(~name="NodeModulesLinker: installing", ());
  let destBinWrapperDir /* local sandbox bin dir */ =
    SandboxSpec.binPath(sandbox.Sandbox.spec);
  let taskQueue = RunAsync.createQueue(40);
  let traverse = JsUtils.getNPMChildren(~fetchDepsSubset, ~solution);
  let f = (promises, hoistedGraphNode) => {
    let nodeModulesPath =
      nodeModulesPathFromParent(
        ~baseNodeModulesPath=Path.(projectPath / "node_modules"),
        hoistedGraphNode,
      );
    HoistedNodeModulesGraph.(
      switch (hoistedGraphNode.parent) {
      | Some(_parentHoistedNodeModulesGraphNode) => [
          RunAsync.submitTask(
            ~queue=taskQueue,
            () => {
              let%lwt () =
                report(
                  "%a",
                  Package.pp,
                  HoistedNodeModulesGraph.nodeData(hoistedGraphNode),
                );
              let* () =
                installPkg(
                  ~installation,
                  ~nodeModulesPath,
                  hoistedGraphNode.data,
                );
              let pkg = hoistedGraphNode.data;
              let pkgName = pkg.Package.name;
              let pkgPath = Path.(nodeModulesPath / pkgName);
              let* pkgJsonOpt = NpmPackageJson.ofDir(pkgPath);
              Stdlib.Option.fold(
                ~some=
                  pkgJson => {
                    let* _: list((string, Path.t)) =
                      Js.linkBins(
                        ~destBinWrapperDir,
                        ~pkgJson,
                        ~srcPackageDir=pkgPath,
                      );
                    RunAsync.return();
                  },
                ~none=RunAsync.return(),
                pkgJsonOpt,
              );
            },
          ),
          ...promises,
        ]

      | None => promises
      }
    );
  };
  let hoistedGraphResult =
    solution
    |> SolutionGraph.iterator
    |> iterateSolution(
         ~traverse,
         ~hoistedGraph=HoistedNodeModulesGraph.init(~traverse),
       );
  switch (hoistedGraphResult) {
  | Ok(hoistedGraph) =>
    let* () =
      hoistedGraph
      |> HoistedNodeModulesGraph.iterator
      |> iterateHoistedNodeModulesGraph(~f, ~init=[])
      |> RunAsync.List.waitAll;
    let%lwt () = finish();
    RunAsync.return();
  | Error(e) => RunAsync.error(e)
  };
};
