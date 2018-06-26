module Version = NpmVersion.Version;

module Packument = {
  module Versions = {
    type t = StringMap.t(Manifest.PackageJson.t);
    let of_yojson: Json.decoder(t) =
      Json.Parse.stringMap(Manifest.PackageJson.of_yojson);
  };

  [@deriving of_yojson({strict: false})]
  type t = {versions: Versions.t};
};

let versions = (~cfg: Config.t, name) => {
  open RunAsync.Syntax;
  let name = Str.global_replace(Str.regexp("/"), "%2f", name);
  let%bind data = Curl.get(cfg.npmRegistry ++ "/" ++ name);
  let%bind packument =
    RunAsync.ofRun(Json.parseStringWith(Packument.of_yojson, data));

  return(
    packument.Packument.versions
    |> StringMap.bindings
    |> List.map(~f=((version, packageJson)) => {
         let manifest = Manifest.ofPackageJson(packageJson);
         (NpmVersion.Version.parseExn(version), manifest);
       }),
  );
};

let version = (~cfg: Config.t, name: string, version: Version.t) => {
  open RunAsync.Syntax;
  let name = Str.global_replace(Str.regexp("/"), "%2f", name);
  let%bind data =
    Curl.get(
      cfg.npmRegistry ++ "/" ++ name ++ "/" ++ Version.toString(version),
    );
  let%bind packageJson =
    RunAsync.ofRun(
      Json.parseStringWith(Manifest.PackageJson.of_yojson, data),
    );
  let manifest = Manifest.ofPackageJson(packageJson);
  return(manifest);
};
