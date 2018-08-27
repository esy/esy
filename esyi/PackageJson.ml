module NpmDependencies = Package.NpmDependencies
module Dependencies = Package.Dependencies

module EsyPackageJson = struct
  type t = {
    _dependenciesForNewEsyInstaller : (NpmDependencies.t option [@default None]);
  } [@@deriving of_yojson { strict = false }]
end

type t = {
  name : (string option [@default None]);
  version : (SemverVersion.Version.t option [@default None]);
  dependencies : (NpmDependencies.t [@default NpmDependencies.empty]);
  devDependencies : (NpmDependencies.t [@default NpmDependencies.empty]);
  esy : (EsyPackageJson.t option [@default None]);
} [@@deriving of_yojson { strict = false }]

let findInDir (path : Path.t) =
  let open RunAsync.Syntax in
  let esyJson = Path.(path / "esy.json") in
  let packageJson = Path.(path / "package.json") in
  if%bind Fs.exists esyJson
  then return (Some esyJson)
  else if%bind Fs.exists packageJson
  then return (Some packageJson)
  else return None

let ofDir path =
  let open RunAsync.Syntax in
  match%bind findInDir path with
  | Some filename ->
    let%bind json = Fs.readJsonFile filename in
    RunAsync.ofRun (Json.parseJsonWith of_yojson json)
  | None -> error "no package.json (or esy.json) found"

let toPackage ~name ~version ~source (pkgJson : t) =
  let originalVersion =
    match pkgJson.version with
    | Some version -> Some (Package.Version.Npm version)
    | None -> None
  in {
    Package.
    name;
    version;
    originalVersion;
    dependencies = Dependencies.NpmFormula pkgJson.dependencies;
    devDependencies = Dependencies.NpmFormula pkgJson.devDependencies;
    source = source, [];
    opam = None;
    kind = if Option.isSome pkgJson.esy then Esy else Npm;
  }
