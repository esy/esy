module Cache = struct

  type t = {
    opamOverrides: (string * OpamVersion.Formula.t * Path.t) list;
    npmPackages: (string, Yojson.Safe.json) Hashtbl.t;
    opamPackages: (string, OpamFile.manifest) Hashtbl.t;
    pkgs: ( (string * Solution.Version.t), Package.t RunAsync.t) Hashtbl.t;
    availableNpmVersions:
      (string, (NpmVersion.Version.t * PackageJson.t) list) Hashtbl.t;
    availableOpamVersions:
      (
        string,
        (OpamVersion.Version.t * OpamFile.ThinManifest.t) list
      ) Hashtbl.t;
  }

  let make ~cfg () =
    let opamOverrides =
      OpamOverrides.getOverrides(cfg.Config.esyOpamOverridePath)
      |> RunAsync.runExn ~err:"unable to read opam overrides"
    in
    {
      availableNpmVersions = Hashtbl.create(100);
      availableOpamVersions = Hashtbl.create(100);
      opamOverrides;
      npmPackages = Hashtbl.create(100);
      opamPackages = Hashtbl.create(100);
      pkgs = Hashtbl.create(100);
    }

end

type t = {
  cfg: Config.t;
  cache: Cache.t;
  cudfVersions: CudfVersions.t;
}

let make ?cache ~cfg () =
  let open RunAsync.Syntax in
  let%bind cache =
    match cache with
    | Some cache -> return cache
    | None -> return (Cache.make ~cfg ())
  in
  return {cfg; cache; cudfVersions = CudfVersions.init ()}
