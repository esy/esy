type t =
  | OfJson({json: Json.t})
  | OfDist({
      dist: Dist.t,
      json: Json.t,
    })
  | OfOpamOverride({
      path: Path.t,
      json: Json.t,
    });

module BuildType = {
  include BuildType;
  include BuildType.AsInPackageJson;
};

[@deriving of_yojson({strict: false})]
type build = {
  [@default None] [@key "buildsInSource"]
  buildType: option(BuildType.t),
  [@default None]
  build: option(CommandList.t),
  [@default None]
  buildDev: option(CommandList.t),
  [@default None]
  install: option(CommandList.t),
  [@default None]
  exportedEnv: option(ExportedEnv.t),
  [@default None]
  exportedEnvOverride: option(ExportedEnv.Override.t),
  [@default None]
  buildEnv: option(BuildEnv.t),
  [@default None]
  buildEnvOverride: option(BuildEnv.Override.t),
};

[@deriving of_yojson({strict: false})]
type install = {
  [@default None]
  dependencies: option(NpmFormula.Override.t),
  [@default None]
  devDependencies: option(NpmFormula.Override.t),
  [@default None]
  resolutions: option(StringMap.t(Resolution.resolution)),
};

let pp = fmt =>
  fun
  | OfJson(_) => Fmt.any("<inline override>", fmt, ())
  | OfDist({dist, json: _}) => Fmt.pf(fmt, "override:%a", Dist.pp, dist)
  | OfOpamOverride(info) =>
    Fmt.pf(fmt, "opam-override:%a", Path.pp, info.path);

let json = override =>
  RunAsync.Syntax.(
    switch (override) {
    | OfJson(info) => return(info.json)
    | OfDist(info) => return(info.json)
    | OfOpamOverride(info) => return(info.json)
    }
  );

let build = override => {
  open RunAsync.Syntax;
  let* json = json(override);
  let* override = RunAsync.ofStringError(build_of_yojson(json));
  return(Some(override));
};

let install = override => {
  open RunAsync.Syntax;
  let* json = json(override);
  let* override = RunAsync.ofStringError(install_of_yojson(json));
  return(Some(override));
};

let ofJson = json => OfJson({json: json});
let ofDist = (json, dist) => OfDist({json, dist});
