open Shared;

let unsatisfied = (map, (name, range)) => {
  switch (Hashtbl.find(map, name)) {
  | exception Not_found => true
  | versions => !List.exists(v => SolveUtils.satisfies(v, range), versions)
  }
};

let findSatisfyingInMap = (map, name, range) => {
  List.find(v => SolveUtils.satisfies(v, range), Hashtbl.find(map, name))
};

let justDepsn = ((_, _, _, deps)) => deps;

let module StringMap = Map.Make({type t = string; let compare = compare});

let makeNpm = ((npmVersionMap, npmToVersions), packages) => {
  let thisLevel = packages |> List.map(((name, range)) => (name, range, findSatisfyingInMap(npmToVersions, name, range)));
  let parentMap = thisLevel |> List.fold_left((map, (name, _, version)) => {
    StringMap.add(name, version, map)
  }, StringMap.empty);
  let rec toNpm = (parentage, name, range, realVersion) => {
    let (manifest, deps) = Hashtbl.find(npmVersionMap, (name, realVersion));
    let thisLevel = deps.Types.npm |> List.map(((name, range)) => {
      switch (StringMap.find_opt(name, parentage)) {
      | Some(v) when SolveUtils.satisfies(v, range) => (name, None)
      | _ => (name, Some((range, findSatisfyingInMap(npmToVersions, name, range))))
      }
    });
    let childMap = thisLevel |> List.fold_left((map, (name, maybe)) => {
      switch maybe {
      | None => map
      | Some((range, version)) => StringMap.add(name, version, map)
      }
    }, parentage);
    Env.Npm.({
      source: Manifest.getSource(manifest, name, realVersion),
      resolved: realVersion,
      requested: range,
      dependencies: thisLevel |> List.map(((name, contents)) => {
        switch contents {
        | None => (name, None)
        | Some((range, real)) => (name, Some(toNpm(childMap, name, range, real)))
        }
      })
    })
  };
  thisLevel |> List.map(((name, range, real)) => (name, toNpm(parentMap, name, range, real)))
};

let makeFullPackage = (name, version, manifest, deps, solvedDeps, buildToVersions, npmPair) => {
    let nameToVersion = Hashtbl.create(100);
    solvedDeps |> List.iter(((name, version, _, _)) => Hashtbl.replace(nameToVersion, name, version));

    Env.({
      package: {
        name,
        version,
        source: Manifest.getSource(manifest, name, version),
        requested: deps,
        runtime: deps.Types.runtime |> List.map(((name, range)) => (name, range, Hashtbl.find(nameToVersion, name))),
        build: deps.Types.build |> List.map(((name, range)) => (name, range, findSatisfyingInMap(buildToVersions, name, range))),
        npm: makeNpm(npmPair, deps.Types.npm),
      },
      runtimeBag: solvedDeps |> List.map(((name, version, manifest, deps)) => {
        name,
        version,
        source: Manifest.getSource(manifest, name, version),
        requested: deps,
        runtime: deps.Types.runtime |> List.map(((name, range)) => (name, range, Hashtbl.find(nameToVersion, name))),
        build: deps.Types.build |> List.map(((name, range)) => (name, range, findSatisfyingInMap(buildToVersions, name, range))),
        npm: [],
      }),
    })
};

let settleBuildDeps = (cache, solvedDeps, requestedBuildDeps) => {
  let allTransitiveBuildDeps = solvedDeps |> List.map(justDepsn) |> List.map(deps => deps.Types.build) |> List.concat;
  /* let allTransitiveBuildDeps = allNeededBuildDeps @ (
    solvedTargets |> List.map(((_, deps)) => getBuildDeps(deps)) |> List.concat |> List.concat
  ); */

  let buildDepsToInstall = allTransitiveBuildDeps @ requestedBuildDeps;
  let nameToVersions = Hashtbl.create(100);
  let versionMap = Hashtbl.create(100);
  let rec loop = (buildDeps) => {
    let toAdd = buildDeps |> List.filter(unsatisfied(nameToVersions));
    if (toAdd != []) {
      let solved = SolveDeps.solveLoose(~cache, ~requested=toAdd, ~current=nameToVersions, ~deep=false);
      solved |> List.map(((name, version, manifest, deps)) => {
        if (!Hashtbl.mem(versionMap, (name, version))) {
          Hashtbl.replace(nameToVersions, name, [
            version,
            ...(Hashtbl.mem(nameToVersions, name) ? Hashtbl.find(nameToVersions, name) : [])
          ]);

          let solvedDeps = SolveDeps.solve(~cache, ~requested=deps.Types.runtime);
          Hashtbl.replace(versionMap, (name, version), (manifest, deps, solvedDeps));
          let childBuilds = solvedDeps |> List.map(justDepsn) |> List.map(deps => deps.Types.build) |> List.concat;
          childBuilds @ deps.Types.build
        } else {
          []
        }
      }) |> List.concat |> buildDeps => {
        loop(buildDeps)
      };
    }
  };

  loop(buildDepsToInstall);

  (versionMap, nameToVersions)
};

let resolveNpm = (cache, npmRequests) => {
  /* Allow relaxing the constraint */
  let solvedDeps = SolveDeps.solve(~cache, ~requested=npmRequests);
  let npmVersionMap = Hashtbl.create(100);
  let npmToVersions = Hashtbl.create(100);
  solvedDeps |> List.iter(((name, version, manifest, deps)) => {
    Hashtbl.replace(npmVersionMap, (name, version), (manifest, deps));
    Hashtbl.replace(npmToVersions, name, [
      version,
      ...Hashtbl.mem(npmToVersions, name) ? Hashtbl.find(npmToVersions, name) : []
    ])
  });
  (npmVersionMap, npmToVersions)
};

let solve = (config, manifest) => {
  SolveUtils.checkRepositories(config);
  let cache = SolveDeps.initCache(config);
  let depsByKind = Manifest.getDeps(manifest);

  let solvedDeps = SolveDeps.solve(~cache, ~requested=depsByKind.runtime);

  /** TODO should targets be determined completely separately?
   * seems like we'll want to be able to ~fetch~  independently...
   * but maybe solve all at once?
   * yeah probably. makes things a little harder for me.
   */
  /*
  let solvedTargets = targets |> List.map(target => {
    let targetDeps = SolveDeps.solveWithAsMuchOverlapAsPossible(
      ~cache,
      ~requested=target.dependencies.runtime,
      ~current=solvedDeps
    );
    (target, targetDeps)
  });
  */

  let (buildVersionMap, buildToVersions) = settleBuildDeps(cache, solvedDeps, depsByKind.build);


  /* Ok, time for npm. */
  let allNpmRequests =
    Hashtbl.fold(((name, version), (manifest, deps, solvedDeps), result) => deps.Types.npm @ (List.map(((_, _, _, deps)) => deps.Types.npm, solvedDeps) |> List.concat) @ result, buildVersionMap, [])
    @ List.concat(List.map(((_, _, _, deps)) => deps.Types.npm, solvedDeps))
    @ depsByKind.npm
   ;
  let npmPair = resolveNpm(cache, allNpmRequests);



  let allBuildPackages = Hashtbl.fold(((name, version), (manifest, deps, solvedDeps), result) => {
    [makeFullPackage(name, version, manifest, deps, solvedDeps, buildToVersions, npmPair), ...result]
  }, buildVersionMap, []);

  let env = {
    Env.targets: [(Env.Default, makeFullPackage("*root*", `File("./"), manifest, depsByKind, solvedDeps, buildToVersions, npmPair))],
    buildDependencies: allBuildPackages,
  };

  Env.map(SolveUtils.lockDownSource, env)
};
