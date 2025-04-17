open EsyPackageConfig;

type override =
  | OfJson({json: Json.t})
  | OfPath(Dist.local)
  | OfOpamOverride({path: DistPath.t});

let override_to_yojson = override =>
  switch (override) {
  | OfJson({json}) => json
  | OfPath(local) => Dist.local_to_yojson(local)
  | OfOpamOverride({path}) =>
    `Assoc([("opamoverride", DistPath.to_yojson(path))])
  };

let override_of_yojson = json =>
  Result.Syntax.(
    switch (json) {
    | `String(_) =>
      let%map local = Dist.local_of_yojson(json);
      OfPath(local);
    | `Assoc([("opamoverride", path)]) =>
      let* path = DistPath.of_yojson(path);
      return(OfOpamOverride({path: path}));
    | `Assoc(_) => return(OfJson({json: json}))
    | _ => error("expected a string or an object")
    }
  );

[@deriving yojson]
type overrides = list(override);

/* This is checksum of all dependencies/resolutios, used as a checksum. */
/* Id of the root package. */
/* Map from ids to nodes. */
[@deriving yojson({strict: false})]
type t = {
  [@key "checksum"]
  digest: string,
  root: PackageId.t,
  node: PackageId.Map.t(node),
  [@default None]
  platformSpecific:
    option(EsyOpamLibs.AvailablePlatforms.Map.t(PackageId.Map.t(node))),
}
and node = {
  id: PackageId.t,
  name: string,
  version: Version.t,
  source: PackageSource.t,
  overrides,
  dependencies: PackageId.Set.t,
  devDependencies: PackageId.Set.t,
  [@default InstallConfig.empty]
  installConfig: InstallConfig.t,
  [@default []]
  extraSources: list(ExtraSource.t),
  [@default None]
  available: option(EsyOpamLibs.AvailablePlatforms.t),
};

let indexFilename = "index.json";

let gitAttributesContents = {|
# Set eol to LF so files aren't converted to CRLF-eol on Windows.
* text eol=lf linguist-generated
|};

let gitIgnoreContents = {|
# Reset any possible .gitignore, we want all esy.lock to be un-ignored.
!*
|};

module PackageOverride = {
  [@deriving of_yojson({strict: false})]
  type t = {override: Json.t};

  let ofPath = path =>
    RunAsync.Syntax.(
      RunAsync.contextf(
        {
          let* json = Fs.readJsonFile(path);
          let* data = RunAsync.ofRun(Json.parseJsonWith(of_yojson, json));
          return(data.override);
        },
        "reading package override %a",
        Path.pp,
        path,
      )
    );
};

let writeOverride = (sandbox, pkg, gitUsername, gitPassword, override) =>
  RunAsync.Syntax.(
    switch (override) {
    | Override.OfJson({json}) => return(OfJson({json: json}))
    | Override.OfOpamOverride(info) =>
      let id =
        Format.asprintf(
          "%s-%a-opam-override",
          pkg.Package.name,
          Version.pp,
          pkg.version,
        );

      let lockPath =
        Path.(
          SandboxSpec.solutionLockPath(sandbox.Sandbox.spec)
          / "overrides"
          / Path.safeSeg(id)
        );
      let* () = Fs.copyPath(~src=info.path, ~dst=lockPath);
      let path =
        DistPath.ofPath(
          Path.tryRelativize(~root=sandbox.spec.path, lockPath),
        );
      return(OfOpamOverride({path: path}));
    | Override.OfDist({dist: Dist.LocalPath(local), json: _}) =>
      return(OfPath(local))
    | Override.OfDist({dist, json: _}) =>
      let* distPath =
        DistStorage.fetchIntoCache(
          sandbox.cfg,
          sandbox.spec,
          dist,
          gitUsername,
          gitPassword,
        );
      let digest = Digestv.ofString(Dist.show(dist));
      let lockPath =
        Path.(
          SandboxSpec.solutionLockPath(sandbox.Sandbox.spec)
          / "overrides"
          / Digestv.toHex(digest)
        );
      let* () = Fs.copyPath(~src=distPath, ~dst=lockPath);
      let* () = Fs.rmPath(Path.(lockPath / ".git"));
      let manifest = Dist.manifest(dist);
      let path =
        DistPath.ofPath(
          Path.tryRelativize(~root=sandbox.spec.path, lockPath),
        );
      return(
        OfPath({
          path,
          manifest,
        }),
      );
    }
  );

let readOverride = (sandbox, override) =>
  RunAsync.Syntax.(
    switch (override) {
    | OfJson({json}) => return(Override.OfJson({json: json}))
    | OfOpamOverride({path}) =>
      let path = DistPath.toPath(sandbox.Sandbox.spec.path, path);
      let* json = Fs.readJsonFile(Path.(path / "package.json"));
      return(
        Override.OfOpamOverride({
          json,
          path,
        }),
      );
    | OfPath(local) =>
      let filename =
        switch (local.manifest) {
        | None => "package.json"
        | Some((Esy, filename)) => filename
        | Some((Opam, _filename)) =>
          failwith("cannot load override from opam file")
        };

      let dist = Dist.LocalPath(local);
      let path =
        DistPath.toPath(
          sandbox.Sandbox.spec.path,
          DistPath.(local.path / filename),
        );
      let* json = PackageOverride.ofPath(path);
      return(
        Override.OfDist({
          dist,
          json,
        }),
      );
    }
  );

let writeOverrides = (sandbox, pkg, overrides, gitUsername, gitPassword) =>
  RunAsync.List.mapAndJoin(
    ~f=writeOverride(sandbox, pkg, gitUsername, gitPassword),
    overrides,
  );

let readOverrides = (sandbox, overrides) =>
  RunAsync.List.mapAndJoin(~f=readOverride(sandbox), overrides);

let writeOpam = (sandbox, opam: PackageSource.opam) => {
  open RunAsync.Syntax;
  let sandboxPath = sandbox.Sandbox.spec.path;
  let opampath = Path.(sandboxPath /\/ opam.path);
  let dst = {
    let name = OpamPackage.Name.to_string(opam.name);
    let version = OpamPackage.Version.to_string(opam.version);
    Path.(
      SandboxSpec.solutionLockPath(sandbox.spec)
      / "opam"
      / (name ++ "." ++ version)
    );
  };

  if (Path.isPrefix(sandboxPath, opampath)) {
    return(opam);
  } else {
    let* () = Fs.copyPath(~src=opam.path, ~dst);
    let path = Path.tryRelativize(~root=sandboxPath, dst);
    return({
      ...opam,
      path,
    });
  };
};

let readOpam = (sandbox, opam: PackageSource.opam) => {
  open RunAsync.Syntax;
  let sandboxPath = sandbox.Sandbox.spec.path;
  let opampath = Path.(sandboxPath /\/ opam.path);
  return({
    ...opam,
    path: opampath,
  });
};

let writePackage = (sandbox, pkg: Package.t, gitUsername, gitPassword) => {
  open RunAsync.Syntax;
  let* source =
    switch (pkg.source) {
    | Link({path, manifest, kind}) =>
      return(
        PackageSource.Link({
          path,
          manifest,
          kind,
        }),
      )
    | Install({source, opam: None}) =>
      return(
        PackageSource.Install({
          source,
          opam: None,
        }),
      )
    | Install({source, opam: Some(opam)}) =>
      let* opam = writeOpam(sandbox, opam);
      return(
        PackageSource.Install({
          source,
          opam: Some(opam),
        }),
      );
    };

  let* overrides =
    writeOverrides(sandbox, pkg, pkg.overrides, gitUsername, gitPassword);
  return({
    id: pkg.id,
    name: pkg.name,
    version: pkg.version,
    source,
    overrides,
    dependencies: pkg.dependencies,
    devDependencies: pkg.devDependencies,
    installConfig: pkg.installConfig,
    extraSources: pkg.extraSources,
    available: Some(pkg.available),
  });
};

let readPackage = (sandbox, node: node) => {
  open RunAsync.Syntax;
  let* source =
    switch (node.source) {
    | Link({path, manifest, kind}) =>
      return(
        PackageSource.Link({
          path,
          manifest,
          kind,
        }),
      )
    | Install({source, opam: None}) =>
      return(
        PackageSource.Install({
          source,
          opam: None,
        }),
      )
    | Install({source, opam: Some(opam)}) =>
      let* opam = readOpam(sandbox, opam);
      return(
        PackageSource.Install({
          source,
          opam: Some(opam),
        }),
      );
    };

  let* overrides = readOverrides(sandbox, node.overrides);

  let* available =
    switch (node.available) {
    | Some(available) => RunAsync.return @@ available
    | None =>
      switch (node.source) {
      | Link({path, manifest: Some((Opam, filename)), kind: _}) =>
        let* opamfile = {
          let path =
            DistPath.(path / filename |> toPath(sandbox.Sandbox.spec.path));
          let* data = Fs.readFile(path);
          let filename =
            OpamFile.make(OpamFilename.of_string(Path.show(path)));
          try(return(OpamFile.OPAM.read_from_string(~filename, data))) {
          | Failure(msg) =>
            errorf("error parsing opam metadata %a: %s", Path.pp, path, msg)
          | _ => error("error parsing opam metadata")
          };
        };
        let availableFilter = OpamFile.OPAM.available(opamfile);
        RunAsync.return @@
        EsyOpamLibs.AvailablePlatforms.filter(
          availableFilter,
          EsyOpamLibs.AvailablePlatforms.default,
        );

      | Link(_) => RunAsync.return @@ EsyOpamLibs.AvailablePlatforms.default
      | Install({source: _, opam: None}) =>
        RunAsync.return @@ EsyOpamLibs.AvailablePlatforms.default
      | Install({source: _, opam: Some(opam)}) =>
        let* opamfile = {
          let path = Path.(opam.path / "opam");
          let* data = Fs.readFile(path);
          let filename =
            OpamFile.make(OpamFilename.of_string(Path.show(path)));
          try(return(OpamFile.OPAM.read_from_string(~filename, data))) {
          | Failure(msg) =>
            errorf("error parsing opam metadata %a: %s", Path.pp, path, msg)
          | _ => error("error parsing opam metadata")
          };
        };
        let availableFilter = OpamFile.OPAM.available(opamfile);
        RunAsync.return @@
        EsyOpamLibs.AvailablePlatforms.filter(
          availableFilter,
          EsyOpamLibs.AvailablePlatforms.default,
        );
      }
    };
  return({
    Package.id: node.id,
    name: node.name,
    version: node.version,
    source,
    overrides,
    dependencies: node.dependencies,
    devDependencies: node.devDependencies,
    installConfig: node.installConfig,
    extraSources: node.extraSources,
    available,
  });
};

let solutionOfLock = (sandbox, root, node) => {
  open RunAsync.Syntax;
  let f = (_id, node, solution) => {
    let* solution = solution;
    let* pkg = readPackage(sandbox, node);
    return(Solution.add(solution, pkg));
  };

  PackageId.Map.fold(f, node, return(Solution.empty(root)));
};

let lockOfSolution = (sandbox, solution: Solution.t, gitUsername, gitPassword) => {
  open RunAsync.Syntax;
  let* node = {
    let f = (pkg, _dependencies, nodes) => {
      let* nodes = nodes;
      let* node = writePackage(sandbox, pkg, gitUsername, gitPassword);
      return(PackageId.Map.add(pkg.Package.id, node, nodes));
    };

    Solution.fold(~f, ~init=return(PackageId.Map.empty), solution);
  };

  return((Solution.root(solution), node));
};

let ofPath = (~digest=?, sandbox: Sandbox.t, path: Path.t) =>
  RunAsync.Syntax.(
    RunAsync.contextf(
      {
        let%lwt () =
          Logs_lwt.debug(m => m("SolutionLock.ofPath %a", Path.pp, path));
        if%bind (Fs.exists(path)) {
          let%lwt lock = {
            let* json = Fs.readJsonFile(Path.(path / indexFilename));
            RunAsync.ofRun(Json.parseJsonWith(of_yojson, json));
          };

          switch (lock) {
          | Ok(lock) =>
            let currentPlatform = (System.Platform.host, System.Arch.host);
            let* node =
              switch (lock.platformSpecific) {
              | Some(platformSpecificNode) =>
                switch (
                  EsyOpamLibs.AvailablePlatforms.Map.find_opt(
                    currentPlatform,
                    platformSpecificNode,
                  )
                ) {
                | Some(node) =>
                  /* TODO: investigate why SolutionLock.ofPath needs to be called multiple times
                     When I logged, I noticed SolutionLock.ofPath
                     gets called multiple times atleast in the [default] command, and
                     possibly so in other commands too. */
                  /* let%lwt () = */
                  /*   Logs_lwt.app(m => */
                  /*     m( */
                  /*       "Found platform specfic solution %a. Using it instead of default", */
                  /*       AvailablePlatforms.ppEntry, */
                  /*       currentPlatform, */
                  /*     ) */
                  /*   ); */
                  RunAsync.return(node)
                | None => RunAsync.return(lock.node)
                }
              | None => RunAsync.return(lock.node)
              };
            switch (digest) {
            | None =>
              let* solution = solutionOfLock(sandbox, lock.root, node);
              return(Some(solution));
            | Some(digest) =>
              if (String.compare(lock.digest, Digestv.toHex(digest)) == 0) {
                let* solution = solutionOfLock(sandbox, lock.root, node);
                return(Some(solution));
              } else {
                return(None);
              }
            };
          | Error(err) =>
            let path =
              Option.orDefault(
                ~default=path,
                Path.relativize(~root=sandbox.spec.path, path),
              );

            errorf(
              "corrupted %a lock@\nyou might want to remove it and install from scratch@\nerror: %a",
              Path.pp,
              path,
              Run.ppError,
              err,
            );
          };
        } else {
          return(None);
        };
      },
      "reading lock %a",
      Path.pp,
      path,
    )
  );

let toPath =
    (
      ~digest,
      sandbox,
      solution: Solution.t,
      platformSpecificSolutions,
      path: Path.t,
      gitUsername,
      gitPassword,
    ) => {
  open RunAsync.Syntax;
  let%lwt () =
    Logs_lwt.debug(m => m("SolutionLock.toPath %a", Path.pp, path));
  let* () = Fs.rmPath(path);
  let* (root, node) =
    lockOfSolution(sandbox, solution, gitUsername, gitPassword);
  let* platformSpecificSolutionsList =
    platformSpecificSolutions
    |> EsyOpamLibs.AvailablePlatforms.Map.bindings
    |> List.map(~f=((k, solution)) => {
         let* (_root, node) =
           // TODO: check if this root matches with solution global root
           lockOfSolution(sandbox, solution, gitUsername, gitPassword);
         RunAsync.return((k, node));
       })
    |> RunAsync.List.joinAll;
  let platformSpecificSolutions =
    List.fold_left(
      ~f=
        (acc, kv) => {
          let (k, v) = kv;
          EsyOpamLibs.AvailablePlatforms.Map.add(k, v, acc);
        },
      ~init=EsyOpamLibs.AvailablePlatforms.Map.empty,
      platformSpecificSolutionsList,
    );
  let lock = {
    digest: Digestv.toHex(digest),
    node,
    root: root.Package.id,
    platformSpecific: Some(platformSpecificSolutions),
  };
  let* () = Fs.createDir(path);
  let* () =
    Fs.writeJsonFile(~json=to_yojson(lock), Path.(path / indexFilename));
  let* () =
    Fs.writeFile(~data=gitAttributesContents, Path.(path / ".gitattributes"));
  let* () = Fs.writeFile(~data=gitIgnoreContents, Path.(path / ".gitignore"));
  return();
};

let unsafeUpdateChecksum = (~digest, path) => {
  open RunAsync.Syntax;
  let* lock = {
    let* json = Fs.readJsonFile(Path.(path / indexFilename));
    RunAsync.ofRun(Json.parseJsonWith(of_yojson, json));
  };

  let lock = {
    ...lock,
    digest: Digestv.toHex(digest),
  };
  Fs.writeJsonFile(~json=to_yojson(lock), Path.(path / indexFilename));
};
