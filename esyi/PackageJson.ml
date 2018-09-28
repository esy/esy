module EsyPackageJson = struct
  type t = {
    _dependenciesForNewEsyInstaller : Package.NpmFormula.t option [@default None];
  } [@@deriving of_yojson { strict = false }]
end

module Manifest = struct
  type t = {
    name : string option [@default None];
    version : SemverVersion.Version.t option [@default None];
    dependencies : Package.NpmFormula.t [@default Package.NpmFormula.empty];
    devDependencies : Package.NpmFormula.t [@default Package.NpmFormula.empty];
    esy : EsyPackageJson.t option [@default None];
    dist : dist option [@default None]
  } [@@deriving of_yojson { strict = false }]

  and dist = {
    tarball : string;
    shasum : string;
  }
end

module ResolutionsOfManifest = struct
  type t = {
    resolutions : (Package.Resolutions.t [@default Package.Resolutions.empty]);
  } [@@deriving of_yojson { strict = false }]
end

let packageOfJson ?(parseResolutions=false) ?source ~name ~version json =
  let open Run.Syntax in
  let%bind pkgJson = Json.parseJsonWith Manifest.of_yojson json in
  let originalVersion =
    match pkgJson.Manifest.version with
    | Some version -> Some (Version.Npm version)
    | None -> None
  in
  let dependencies =
    match pkgJson.esy with
    | None
    | Some {EsyPackageJson. _dependenciesForNewEsyInstaller= None} ->
      pkgJson.dependencies
    | Some {EsyPackageJson. _dependenciesForNewEsyInstaller= Some dependencies} ->
      dependencies
  in
  let%bind resolutions =
    match parseResolutions with
    | false -> return Package.Resolutions.empty
    | true ->
      let%bind {ResolutionsOfManifest. resolutions} =
        Json.parseJsonWith ResolutionsOfManifest.of_yojson json
      in
      return resolutions
  in

  let%bind source =
    match source, pkgJson.dist with
    | Some source, _ -> return source
    | None, Some dist ->
      return (Source.Archive {
        url = dist.tarball;
        checksum = Checksum.Sha1, dist.shasum;
      })
    | None, None ->
      error "unable to determine package source, missing 'dist' metadata"
  in

  return {
    Package.
    name;
    version;
    originalVersion;
    originalName = pkgJson.name;
    dependencies = Package.Dependencies.NpmFormula dependencies;
    devDependencies = Package.Dependencies.NpmFormula pkgJson.devDependencies;
    resolutions;
    source = source, [];
    overrides = Package.Overrides.empty;
    opam = None;
    kind = if Option.isSome pkgJson.esy then Esy else Npm;
  }
