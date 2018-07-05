module Version = SemverVersion.Version
module String = Astring.String
module Resolutions = Package.Resolutions
module Source = Package.Source
module Dependencies = Package.Dependencies

(* This is used just to read the Json.t *)
module PackageJson = struct
  type t = {
    name : string;
    version : string;
    resolutions : (Resolutions.t [@default Resolutions.empty]);
    dependencies : (Dependencies.t [@default Dependencies.empty]);
    devDependencies : (Dependencies.t [@default Dependencies.empty]);
    dist : (dist option [@default None]);
    esy : (Json.t option [@default None]);
  } [@@deriving of_yojson { strict = false }]

  and dist = {
    tarball : string;
    shasum : string;
  }

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind data = Fs.readJsonFile path in
    let%bind pkgJson = RunAsync.ofRun (Json.parseJsonWith of_yojson data) in
    return pkgJson

  let ofDir (path : Path.t) =
    let open RunAsync.Syntax in
    let esyJson = Path.(path / "esy.json") in
    let packageJson = Path.(path / "package.json") in
    if%bind Fs.exists esyJson
    then ofFile esyJson
    else if%bind Fs.exists packageJson
    then ofFile packageJson
    else error "no package.json found"
end

type t = {
  name : string;
  version : string;
  dependencies : Dependencies.t;
  devDependencies : Dependencies.t;
  source : Source.t;
  hasEsyManifest : bool;
}

type manifest = t

let name manifest = manifest.name
let version manifest = Version.parseExn manifest.version

let ofPackageJson ?(source=Source.NoSource) (pkgJson : PackageJson.t) = {
  name = pkgJson.name;
  version = pkgJson.version;
  dependencies = pkgJson.dependencies;
  devDependencies = pkgJson.devDependencies;
  hasEsyManifest = Option.isSome pkgJson.esy;
  source =
    match pkgJson.dist with
    | Some dist -> Source.Archive (dist.PackageJson.tarball, dist.PackageJson.shasum)
    | None -> source;
}

let of_yojson json =
  let open Result.Syntax in
  let%bind pkgJson = PackageJson.of_yojson json in
  return (ofPackageJson pkgJson)

let ofDir (path : Path.t) =
  let open RunAsync.Syntax in
  let%bind pkgJson = PackageJson.ofDir path in
  return (ofPackageJson pkgJson)

module Root = struct
  type t = {
    manifest : manifest;
    resolutions : Resolutions.t;
  }

  let ofDir (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind pkgJson = PackageJson.ofDir path in
    let manifest = ofPackageJson pkgJson in
    return {manifest; resolutions = pkgJson.PackageJson.resolutions}
end

let toPackage ?name ?version (manifest : t) =
  let open Run.Syntax in
  let name =
    match name with
    | Some name -> name
    | None -> manifest.name
  in
  let version =
    match version with
    | Some version -> version
    | None -> Package.Version.Npm (SemverVersion.Version.parseExn manifest.version)
  in
  let source =
    match version with
    | Package.Version.Source src -> src
    | _ -> manifest.source
  in
  return {
    Package.
    name;
    version;
    dependencies = manifest.dependencies;
    devDependencies = manifest.devDependencies;
    source;
    opam = None;
    kind =
      if manifest.hasEsyManifest
      then Esy
      else Npm
  }

