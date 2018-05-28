open Opam;
open Npm;

module Path = EsyLib.Path;
module Lockfile = Shared.Lockfile;

let getDeps = manifest => {
  let depsByKind =
    switch (manifest) {
    | `OpamFile(opam) => OpamFile.process(opam)
    | `PackageJson(json) => PackageJson.process(json)
    };
  depsByKind;
};

let getSource = (manifest, name, version) =>
  switch (version) {
  | Lockfile.Github(user, repo, ref) =>
    Shared.Types.PendingSource.GithubSource(user, repo, ref)
  | Lockfile.LocalPath(path) =>
    Shared.Types.PendingSource.File(Path.toString(path))
  | _ =>
    switch (manifest) {
    | `OpamFile(opam) =>
      Shared.Types.PendingSource.WithOpamFile(
        OpamFile.getSource(opam),
        OpamFile.toPackageJson(opam, name, version),
      )
    | `PackageJson(json) => PackageJson.getSource(json)
    }
  };
