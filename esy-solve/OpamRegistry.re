open EsyPackageConfig;
module String = Astring.String;

module OpamPathsByVersion =
  Memoize.Make({
    type key = OpamPackage.Name.t;
    type value = RunAsync.t(option(OpamPackage.Version.Map.t(Path.t)));
  });

type t = {
  init: unit => RunAsync.t(registry),
  lock: Lwt_mutex.t,
  mutable registry: option(registry),
}
and registry = {
  version: option(OpamVersion.t),
  repoPath: Path.t,
  overrides: OpamOverrides.t,
  pathsCache: OpamPathsByVersion.t,
  opamCache: OpamManifest.File.Cache.t,
};

let readOpamFileOfRegistry = (res, registry) => {
  let path = Path.(OpamResolution.path(res) / "opam");
  OpamManifest.File.ofPath(
    ~upgradeIfOpamVersionIsLessThan=?registry.version,
    ~cache=registry.opamCache,
    path,
  );
};

let readUrlFileOfRegistry = (res, _registry) => {
  open RunAsync.Syntax;
  let path = Path.(OpamResolution.path(res) / "url");
  if%bind (Fs.exists(path)) {
    let* data = Fs.readFile(path);
    return(Some(OpamFile.URL.read_from_string(data)));
  } else {
    return(None);
  };
};

let make = (~opamRepository, ~cfg, ()) => {
  let init = () => {
    open RunAsync.Syntax;
    let* repoPath =
      switch (opamRepository) {
      | Config.Local(local) => return(local)
      | Config.Remote(remote, branchOpt, local) =>
        let branch = Option.orDefault(~default="master", branchOpt);
        let update = () => {
          let%lwt () =
            Logs_lwt.app(m =>
            m(
              "%s %s %s %s %s",
              <Pastel dim=true> "checking" </Pastel>,
              remote,
              <Pastel dim=true> "branch" </Pastel>,
              branch,
              <Pastel dim=true> "for updates..." </Pastel>,
            )
          );
          let* () =
            Git.ShallowClone.update(~branch, ~dst=local, remote);
          return(local);
        };

        if (cfg.Config.skipRepositoryUpdate) {
          if%bind (Fs.exists(local)) {
            return(local);
          } else {
            update();
          };
        } else {
          update();
        };
      };

    let* overrides = OpamOverrides.init(~cfg, ());

    let* repo = {
      let path = Path.(repoPath / "repo");
      let* data = Fs.readFile(path);
      let filename = OpamFile.make(OpamFilename.of_string(Path.show(path)));
      let repo = OpamFile.Repo.read_from_string(~filename, data);
      return(repo);
    };

    return({
      version: OpamFile.Repo.opam_version(repo),
      repoPath,
      pathsCache: OpamPathsByVersion.make(),
      opamCache: OpamManifest.File.Cache.make(),
      overrides,
    });
  };
  {
    init,
    lock: Lwt_mutex.create(),
    registry: None,
  };
};

let initRegistry = (registry: t) => {
  let init = () =>
    RunAsync.Syntax.(
      switch (registry.registry) {
      | Some(v) => return(v)
      | None =>
        let* v = registry.init();
        registry.registry = Some(v);
        return(v);
      }
    );

  Lwt_mutex.with_lock(registry.lock, init);
};

let getPackageVersionIndex = (registry: registry, ~name: OpamPackage.Name.t) => {
  open RunAsync.Syntax;
  let read = () => {
    let name = OpamPackage.Name.to_string(name);
    let path = Path.(registry.repoPath / "packages" / name);
    if%bind (Fs.isDir(path)) {
      let* entries = Fs.listDir(path);
      let f = (index, entry) => {
        let versionPath = Path.(path / entry);
        if%bind (Fs.isDir(versionPath)) {
          let version =
            switch (String.cut(~sep=".", entry)) {
            | None => OpamPackage.Version.of_string("")
            | Some((_name, version)) =>
              OpamPackage.Version.of_string(version)
            };
          return(OpamPackage.Version.Map.add(version, versionPath, index));
        } else {
          return(index);
        };
      };

      let* index =
        RunAsync.List.foldLeft(
          ~init=OpamPackage.Version.Map.empty,
          ~f,
          entries,
        );
      return(Some(index));
    } else {
      return(None);
    };
  };

  OpamPathsByVersion.compute(registry.pathsCache, name, read);
};

let findPackagePath = ((name, version), registry) => {
  open RunAsync.Syntax;
  switch%bind (getPackageVersionIndex(registry, ~name)) {
  | None =>
    errorf("no opam package %s found", OpamPackage.Name.to_string(name))
  | Some(index) =>
    switch (OpamPackage.Version.Map.find_opt(version, index)) {
    | None =>
      errorf(
        "no opam package %s@%s found",
        OpamPackage.Name.to_string(name),
        OpamPackage.Version.to_string(version),
      )
    | Some(path) => return(path)
    }
  };
};

let resolve =
    (
      ~os=?,
      ~arch=?,
      ~ocamlVersion=?,
      ~name: OpamPackage.Name.t,
      ~version: OpamPackage.Version.t,
      registry: registry,
    ) => {
  open RunAsync.Syntax;
  let* path = findPackagePath((name, version), registry);
  let res = OpamResolution.make(name, version, path);
  let* available = {
    let env = (var: OpamVariable.Full.t) => {
      let scope = OpamVariable.Full.scope(var);
      let name = OpamVariable.Full.variable(var);
      let v =
        Option.Syntax.(
          OpamVariable.(
            switch (scope, OpamVariable.to_string(name)) {
            | (OpamVariable.Full.Global, "preinstalled") =>
              return(bool(false))
            | (OpamVariable.Full.Global, "os") =>
              open System.Platform;
              let* os = os;
              // We could have avoided the following altogether if the System.Platform implementation
              // matched opam's. TODO
              let sys =
                switch (os) {
                | Darwin => "macos"
                | Linux => "linux"
                | Cygwin => "cygwin"
                | Unix => "unix"
                | Windows => "win32"
                | Unknown => "unknown"
                };
              return(string(sys));
            | (OpamVariable.Full.Global, "arch") =>
              let* arch = arch;
              return(string(System.Arch.show(arch)));
            | (OpamVariable.Full.Global, "compiler")
            | (OpamVariable.Full.Global, "ocaml-version") =>
              let* ocamlVersion = ocamlVersion;
              return(string(OpamPackage.Version.to_string(ocamlVersion)));
            | (OpamVariable.Full.Global, "os") =>
              switch (System.Platform.host) {
              | Darwin => return(string("macos"))
              | Linux => return(string("linux"))
              // Only 12 opam files reference "cygwin" as an `os`, so we use win32
              | Cygwin => return(string("win32"))
              | Windows => return(string("win32"))
              | Unix => return(string("unix"))
              | Unknown => None
              }
            | (OpamVariable.Full.Global, "arch") =>
              switch (System.Arch.host) {
              | X86_32 => return(string("x86_32"))
              | X86_64 => return(string("x86_64"))
              | Ppc32 => return(string("ppc32"))
              | Ppc64 => return(string("ppc64"))
              | Arm32 => return(string("arm32"))
              | Arm64 => return(string("arm64"))
              | Unknown => None
              }
            | (OpamVariable.Full.Global, _) => None
            | (OpamVariable.Full.Self, _) => None
            | (OpamVariable.Full.Package(_), _) => None
            }
          )
        );
      v;
    };

    let* opam = readOpamFileOfRegistry(res, registry);
    let formula = OpamFile.OPAM.available(opam);
    let%lwt () =
      Logs_lwt.debug(m =>
        m(
          "Evaluating filter %s for opam package %s version %s",
          OpamFilter.to_string(formula),
          OpamPackage.Name.to_string(name),
          OpamPackage.Version.to_string(version),
        )
      );
    let available = OpamFilter.eval_to_bool(~default=true, env, formula);
    return(available);
  };

  if (available) {
    return(Some(res));
  } else {
    return(None);
  };
};

/* Some opam packages don't make sense for esy. */
let isEnabledForEsy = name =>
  switch (OpamPackage.Name.to_string(name)) {
  | "ocaml-system" => false
  | _ => true
  };

let versions =
    (
      ~os=?,
      ~arch=?,
      ~ocamlVersion=?,
      ~name: OpamPackage.Name.t,
      fetchedRegistry: registry,
    ) =>
  RunAsync.Syntax.(
    if (!isEnabledForEsy(name)) {
      return([]);
    } else {
      switch%bind (getPackageVersionIndex(fetchedRegistry, ~name)) {
      | None => return([])
      | Some(index) =>
        let* resolutions = {
          let getPackageVersion = version =>
            resolve(
              ~os?,
              ~arch?,
              ~ocamlVersion?,
              ~name,
              ~version,
              fetchedRegistry,
            );

          RunAsync.List.mapAndJoin(
            ~concurrency=2,
            ~f=((version, _path)) => getPackageVersion(version),
            OpamPackage.Version.Map.bindings(index),
          );
        };

        return(List.filterNone(resolutions));
      };
    }
  );

let version = (~name: OpamPackage.Name.t, ~version, registry) =>
  RunAsync.Syntax.(
    if (!isEnabledForEsy(name)) {
      return(None);
    } else {
      let* registry = initRegistry(registry);
      switch%bind (resolve(~name, ~version, registry)) {
      | None => return(None)
      | Some(res) =>
        let* manifest = {
          let* opam = readOpamFileOfRegistry(res, registry);
          let* url =
            switch (OpamFile.OPAM.url(opam)) {
            | Some(url) => return(Some(url))
            | None => readUrlFileOfRegistry(res, registry)
            };

          return({
            OpamManifest.name,
            version,
            opam,
            url,
            override: None,
            opamRepositoryPath: Some(OpamResolution.path(res)),
          });
        };

        switch%bind (OpamOverrides.find(~name, ~version, registry.overrides)) {
        | None => return(Some(manifest))
        | Some(override) =>
          let manifest = {
            ...manifest,
            OpamManifest.override: Some(override),
          };
          return(Some(manifest));
        };
      };
    }
  );
