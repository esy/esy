type t = {
  cfg : Config.t;
  path : Path.t;
  resolutions : Manifest.Resolutions.t;
  root : Package.t;
}

module Read = struct
  module ParseResolutions = struct
    type t = {
      resolutions : (Package.Resolutions.t [@default Package.Resolutions.empty]);
    } [@@deriving of_yojson { strict = false }]
  end

  let ofDir (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind filename = Manifest.find path in
    let%bind json = Fs.readJsonFile filename in
    let%bind pkgJson = RunAsync.ofRun (Json.parseJsonWith Manifest.PackageJson.of_yojson json) in
    let%bind resolutions = RunAsync.ofRun (Json.parseJsonWith ParseResolutions.of_yojson json) in
    let manifest = Manifest.ofPackageJson pkgJson in
    return (manifest, resolutions.ParseResolutions.resolutions)
end


let ofDir ~cfg (path : Path.t) =
  let open RunAsync.Syntax in
  let%bind root, resolutions = Read.ofDir path in
  let%bind root =
    let version = Package.Version.Source (Package.Source.LocalPath path) in
    Manifest.toPackage ~version root
  in
  return {cfg; root; resolutions; path}
