module Cache = struct
  type t = {
    opamOverrides: (string * OpamVersion.Formula.t * Path.t) list;
    npmPackages: (string, Yojson.Safe.json) Hashtbl.t;
    opamPackages: (string, OpamFile.manifest) Hashtbl.t;
    versions: VersionCache.t;
    manifests:
      (
        (string * Solution.Version.t),
        (Manifest.t * PackageJson.DependenciesInfo.t)
      ) Hashtbl.t;
  }

  let make ~cfg () =
    let opamOverrides =
      OpamOverrides.getOverrides(cfg.Config.esyOpamOverridePath)
      |> RunAsync.runExn ~err:"unable to read opam overrides"
    in
    {
      versions = {
        availableNpmVersions = Hashtbl.create(100);
        availableOpamVersions = Hashtbl.create(100);
        config = cfg;
      };
      opamOverrides;
      npmPackages = Hashtbl.create(100);
      opamPackages = Hashtbl.create(100);
      manifests = Hashtbl.create(100);
    }
end


type t = {
  cache: Cache.t;
  cudfVersions: CudfVersions.t;
}
