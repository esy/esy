module VersionSpec = PackageInfo.VersionSpec;
module SourceSpec = PackageInfo.SourceSpec;

module Version = PackageInfo.Version;
module Source = PackageInfo.Source;

let satisfies = (realVersion, req) =>
  switch (req, realVersion) {
  | (
      VersionSpec.Source(SourceSpec.Github(user, repo, Some(ref))),
      Version.Source(Source.Github(user_, repo_, ref_)),
    )
      when user == user_ && repo == repo_ && ref == ref_ =>
    true
  | (VersionSpec.Npm(semver), Version.Npm(s))
      when NpmVersion.Formula.matches(semver, s) =>
    true
  | (VersionSpec.Opam(semver), Version.Opam(s))
      when OpamVersion.Formula.matches(semver, s) =>
    true
  | (
      VersionSpec.Source(SourceSpec.LocalPath(p1)),
      Version.Source(Source.LocalPath(p2)),
    )
      when Path.equal(p1, p2) =>
    true
  | _ => false
  };

let checkRepositories = config =>
  RunAsync.Syntax.(
    {
      let%bind () =
        Git.ShallowClone.update(
          ~branch="4",
          ~dst=config.Config.esyOpamOverridePath,
          "https://github.com/esy-ocaml/esy-opam-override",
        )
      and () =
        Git.ShallowClone.update(
          ~branch="master",
          ~dst=config.Config.opamRepositoryPath,
          "https://github.com/ocaml/opam-repository",
        );
      return();
    }
  );

let runSolver = (~strategy="-notuptodate", rootName, deps, universe) => {
  let root = {
    ...Cudf.default_package,
    package: rootName,
    version: 1,
    depends: deps,
  };
  Cudf.add_package(universe, root);
  let request = {
    ...Cudf.default_request,
    install: [(root.Cudf.package, Some((`Eq, root.Cudf.version)))],
  };
  let preamble = Cudf.default_preamble;
  let solution =
    Mccs.resolve_cudf(
      ~verbose=false,
      ~timeout=5.,
      strategy,
      (preamble, universe, request),
    );
  switch (solution) {
  | None => None
  | Some((_preamble, universe)) =>
    let packages = Cudf.get_packages(~filter=p => p.Cudf.installed, universe);
    Some(packages);
  };
};
