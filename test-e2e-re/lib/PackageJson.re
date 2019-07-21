open EsyPackageConfig;

module Json = EsyLib.Json;
module Result = EsyLib.Result;

[@deriving (ord, of_yojson({strict: false}), to_yojson)]
type t = {
  name: string,
  version: Version.t,
  [@default NpmFormula.empty]
  dependencies: NpmFormula.t,
  [@default NpmFormula.empty]
  peerDependencies: NpmFormula.t,
  [@default NpmFormula.empty]
  devDependencies: NpmFormula.t,
};

let fromString = data => {
  Json.parseStringWith(of_yojson, data) |> Shared.runRToFpathR;
};

let toString = data => {
  data |> to_yojson |> Yojson.Safe.to_string;
};

let make = (~name, ~version, ()) => {
  {
    name,
    version: Version.parseExn(version),
    dependencies: NpmFormula.empty,
    peerDependencies: NpmFormula.empty,
    devDependencies: NpmFormula.empty,
  };
};

let meta = packageJson => {
  (packageJson.name, packageJson.version);
};
