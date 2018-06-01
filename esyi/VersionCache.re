open SolveUtils;

type t = {
  config: Config.t,
  availableNpmVersions:
    Hashtbl.t(string, list((NpmVersion.t, Yojson.Safe.json))),
  availableOpamVersions:
    Hashtbl.t(string, list((Types.opamConcrete, OpamFile.ThinManifest.t))),
};

let getAvailableVersions = (~cfg: Config.t, ~cache: t, req) =>
  switch (req.PackageJson.DependencyRequest.req) {
  | PackageJson.DependencyRequest.Github(user, repo, ref) => [
      `Github((user, repo, ref)),
    ]
  | Npm(semver) =>
    if (! Hashtbl.mem(cache.availableNpmVersions, req.name)) {
      Hashtbl.replace(
        cache.availableNpmVersions,
        req.name,
        NpmRegistry.getFromNpmRegistry(cfg, req.name),
      );
    };
    let available = Hashtbl.find(cache.availableNpmVersions, req.name);
    available
    |> List.sort(((va, _), (vb, _)) => NpmVersion.compare(va, vb))
    |> List.mapi((i, (v, j)) => (v, j, i))
    |> List.filter(((version, _json, _i)) =>
         NpmVersion.matches(semver, version)
       )
    |> List.map(((version, json, i)) => `Npm((version, json, i)));
  | Opam(semver) =>
    if (! Hashtbl.mem(cache.availableOpamVersions, req.name)) {
      let info =
        OpamRegistry.getFromOpamRegistry(cache.config, req.name)
        |> RunAsync.runExn(~err="unable to get info on opam package");
      Hashtbl.replace(cache.availableOpamVersions, req.name, info);
    };
    let available =
      Hashtbl.find(cache.availableOpamVersions, req.name)
      |> List.sort(((va, _), (vb, _)) => OpamVersion.compare(va, vb))
      |> List.mapi((i, (v, j)) => (v, j, i));
    let matched =
      available
      |> List.filter(((version, _path, _i)) =>
           OpamVersion.matches(semver, version)
         );
    let matched =
      if (matched == []) {
        available
        |> List.filter(((version, _path, _i)) =>
             OpamVersion.matches(tryConvertingOpamFromNpm(semver), version)
           );
      } else {
        matched;
      };
    matched |> List.map(((version, path, i)) => `Opam((version, path, i)));
  | Git(_) => failwith("git dependencies are not supported")
  | LocalPath(p) => [`LocalPath(p)]
  };
