type t =
  | Opam(OpamFile.manifest)
  /* TODO: PackageJson should have parsed manifest instead */
  | PackageJson(Json.t);

let getDeps = manifest => {
  let depsByKind =
    switch (manifest) {
    | Opam(opam) => OpamFile.getDependenciesInfo(opam)
    | PackageJson(json) =>
      /* TODO: refactor that away */
      switch (PackageJson.DependenciesInfo.of_yojson(json)) {
      | Ok(v) => v
      | Error(err) => failwith(err)
      }
    };
  depsByKind;
};

let getSource = (manifest, name, version) =>
  switch (version) {
  | Solution.Version.Github(user, repo, ref) =>
    Types.PendingSource.GithubSource(user, repo, ref)
  | Solution.Version.LocalPath(path) =>
    Types.PendingSource.File(Path.toString(path))
  | _ =>
    switch (manifest) {
    | Opam(opam) =>
      Types.PendingSource.WithOpamFile(
        OpamFile.getSource(opam),
        OpamFile.toPackageJson(opam, name, version),
      )
    | PackageJson(json) => PackageJson.getSource(json)
    }
  };
