type t =
  | Opam(OpamFile.manifest)
  | PackageJson(PackageJson.t);

let name = manifest =>
  switch (manifest) {
  | Opam(manifest) => OpamFile.name(manifest)
  | PackageJson(manifest) => PackageJson.name(manifest)
  };

let version = manifest =>
  switch (manifest) {
  | Opam(manifest) => Solution.Version.Opam(OpamFile.version(manifest))
  | PackageJson(manifest) =>
    Solution.Version.Npm(PackageJson.version(manifest))
  };

let dependencies = manifest =>
  switch (manifest) {
  | Opam(manifest) => OpamFile.dependencies(manifest)
  | PackageJson(manifest) => PackageJson.dependencies(manifest)
  };

let source = (manifest, version) =>
  switch (version) {
  | Solution.Version.Github(user, repo, ref) =>
    Run.return(Types.PendingSource.GithubSource(user, repo, ref))
  | Solution.Version.LocalPath(path) =>
    Run.return(Types.PendingSource.File(Path.toString(path)))
  | _ =>
    switch (manifest) {
    | Opam(manifest) =>
      Run.return(
        Types.PendingSource.WithOpamFile(
          OpamFile.source(manifest),
          OpamFile.toPackageJson(manifest, version),
        ),
      )
    | PackageJson(json) => PackageJson.source(json)
    }
  };

module Github = {
  let getManifest = (user, repo, ref) => {
    open RunAsync.Syntax;
    let fetchFile = name => {
      let url =
        "https://raw.githubusercontent.com/"
        ++ user
        ++ "/"
        ++ repo
        ++ "/"
        ++ Option.orDefault(~default="master", ref)
        ++ "/"
        ++ name;
      Curl.get(url);
    };
    switch%lwt (fetchFile("esy.json")) {
    | Ok(data) =>
      let%bind packageJson =
        RunAsync.ofRun(Json.parseStringWith(PackageJson.of_yojson, data));
      return(PackageJson(packageJson));
    | Error(_) =>
      switch%lwt (fetchFile("package.json")) {
      | Ok(text) =>
        let%bind packageJson =
          RunAsync.ofRun(Json.parseStringWith(PackageJson.of_yojson, text));
        return(PackageJson(packageJson));
      | Error(_) => error("no manifest found")
      }
    };
  };
};
