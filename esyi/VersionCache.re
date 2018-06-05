type t = {
  config: Config.t,
  availableNpmVersions:
    Hashtbl.t(string, list((NpmVersion.t, PackageJson.t))),
  availableOpamVersions:
    Hashtbl.t(
      string,
      list((OpamVersioning.Version.t, OpamFile.ThinManifest.t)),
    ),
};

let getAvailableVersions = (~cfg: Config.t, ~cache: t, req) =>
  RunAsync.Syntax.(
    switch (req.PackageJson.DependencyRequest.req) {
    | PackageJson.DependencyRequest.Github(user, repo, ref) =>
      return([`Github((user, repo, ref))])
    | Npm(semver) =>
      let%bind () =
        if (! Hashtbl.mem(cache.availableNpmVersions, req.name)) {
          let%bind versions = NpmRegistry.resolve(~cfg, req.name);
          Hashtbl.replace(cache.availableNpmVersions, req.name, versions);
          return();
        } else {
          return();
        };
      let available = Hashtbl.find(cache.availableNpmVersions, req.name);
      return(
        available
        |> List.sort(((va, _), (vb, _)) => NpmVersion.compare(va, vb))
        |> List.mapi((i, (v, j)) => (v, j, i))
        |> List.filter(((version, _json, _i)) =>
             NpmVersion.matches(semver, version)
           )
        |> List.map(((version, json, i)) => `Npm((version, json, i))),
      );
    | Opam(semver) =>
      let%bind () =
        if (! Hashtbl.mem(cache.availableOpamVersions, req.name)) {
          let info =
            OpamRegistry.getFromOpamRegistry(cache.config, req.name)
            |> RunAsync.runExn(~err="unable to get info on opam package");
          Hashtbl.replace(cache.availableOpamVersions, req.name, info);
          return();
        } else {
          return();
        };
      let available =
        Hashtbl.find(cache.availableOpamVersions, req.name)
        |> List.sort(((va, _), (vb, _)) =>
             OpamVersioning.Version.compare(va, vb)
           )
        |> List.mapi((i, (v, j)) => (v, j, i));
      let matched =
        available
        |> List.filter(((version, _path, _i)) =>
             OpamVersioning.Formula.matches(semver, version)
           );
      let matched =
        if (matched == []) {
          available
          |> List.filter(((version, _path, _i)) =>
               OpamVersioning.Formula.matches(semver, version)
             );
        } else {
          matched;
        };
      return(
        matched
        |> List.map(((version, path, i)) => `Opam((version, path, i))),
      );
    | Git(_) => error("git dependencies are not supported")
    | LocalPath(p) => return([`LocalPath(p)])
    }
  );
