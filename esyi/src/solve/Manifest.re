open Opam;
open Npm;

let getDeps = manifest => {
  let depsByKind = switch manifest {
  | `OpamFile(opam) => OpamFile.process(opam)
  | `PackageJson(json) => PackageJson.process(json)
  };
  depsByKind
};

let getSource = (manifest, name, version) =>
  switch version {
    | `Github(user, repo, ref) => Shared.Types.PendingSource.GithubSource(user, repo, ref)
    | `File(path) => Shared.Types.PendingSource.File(path)
    | _ => switch manifest {
      | `OpamFile(opam) => Shared.Types.PendingSource.WithOpamFile(OpamFile.getSource(opam), OpamFile.toPackageJson(opam, name, version))
      | `PackageJson(json) => PackageJson.getSource(json)
      };
    };