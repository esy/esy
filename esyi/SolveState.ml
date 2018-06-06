module Cache = struct
  module Packages = Memoize.Make(struct
    type key = (string * Solution.Version.t)
    type value = Package.t RunAsync.t
  end)

  module NpmPackages = Memoize.Make(struct
    type key = string
    type value = (NpmVersion.Version.t * PackageJson.t) list RunAsync.t
  end)

  module OpamPackages = Memoize.Make(struct
    type key = string
    type value = (OpamVersion.Version.t * OpamFile.ThinManifest.t) list RunAsync.t
  end)

  type t = {
    opamOverrides: OpamOverrides.t;
    npmPackages: (string, Yojson.Safe.json) Hashtbl.t;
    opamPackages: (string, OpamFile.manifest) Hashtbl.t;

    pkgs: Packages.t;
    availableNpmVersions: NpmPackages.t;
    availableOpamVersions: OpamPackages.t;
  }

  let make ~cfg () =
    let opamOverrides =
      OpamOverrides.getOverrides(cfg.Config.esyOpamOverridePath)
      |> RunAsync.runExn ~err:"unable to read opam overrides"
    in
    {
      availableNpmVersions = NpmPackages.make ();
      availableOpamVersions = OpamPackages.make ();
      opamOverrides;
      npmPackages = Hashtbl.create(100);
      opamPackages = Hashtbl.create(100);
      pkgs = Packages.make ();
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
