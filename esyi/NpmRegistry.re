module Packument = {
  module Versions = {
    type t = StringMap.t(PackageJson.t);
    let of_yojson: Json.decoder(t) =
      Json.Parse.stringMap(PackageJson.of_yojson);
  };

  [@deriving of_yojson({strict: false})]
  type t = {versions: Versions.t};
};

let resolve = (~cfg: Config.t, name) => {
  open RunAsync.Syntax;
  let name = Str.global_replace(Str.regexp("/"), "%2f", name);
  let%bind data = Curl.get(cfg.npmRegistry ++ "/" ++ name);
  let%bind packument =
    RunAsync.ofRun(Json.parseStringWith(Packument.of_yojson, data));

  return(
    packument.Packument.versions
    |> StringMap.bindings
    |> List.map(((version, manifest)) =>
         (NpmVersion.Version.parseExn(version), manifest)
       ),
  );
};
