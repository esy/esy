module Version = NpmVersion.Version
module String = Astring.String
module Resolutions = PackageInfo.Resolutions
module Source = PackageInfo.Source
module Dependencies = PackageInfo.Dependencies

(* This is used just to read the Json.t *)
module PackageJson = struct
  type t = {
    name : string;
    version : string;
    resolutions : (Resolutions.t [@default Resolutions.empty]);
    dependencies : (Dependencies.t [@default Dependencies.empty]);
    devDependencies : (Dependencies.t [@default Dependencies.empty]);
    dist : (dist option [@default None]);
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
}

type manifest = t

let name manifest = manifest.name
let version manifest = Version.parseExn manifest.version

let ofPackageJson ?(source=Source.NoSource) (pkgJson : PackageJson.t) = {
  name = pkgJson.name;
  version = pkgJson.version;
  dependencies = pkgJson.dependencies;
  devDependencies = pkgJson.devDependencies;
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
