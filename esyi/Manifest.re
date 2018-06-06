type t =
  | Opam(OpamFile.manifest)
  | PackageJson(PackageJson.t);

let dependencies = manifest =>
  switch (manifest) {
  | Opam(manifest) => OpamFile.getDependenciesInfo(manifest)
  | PackageJson(manifest) => PackageJson.dependencies(manifest)
  };

let source = (manifest, name, version) =>
  switch (version) {
  | Solution.Version.Github(user, repo, ref) =>
    Run.return(Types.PendingSource.GithubSource(user, repo, ref))
  | Solution.Version.LocalPath(path) =>
    Run.return(Types.PendingSource.File(Path.toString(path)))
  | _ =>
    switch (manifest) {
    | Opam(opam) =>
      Run.return(
        Types.PendingSource.WithOpamFile(
          OpamFile.source(opam),
          OpamFile.toPackageJson(opam, name, version),
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
