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

let pp: Fmt.t(t);

type build = {
  buildType: option(BuildType.t),
  build: option(CommandList.t),
  buildDev: option(CommandList.t),
  install: option(CommandList.t),
  exportedEnv: option(ExportedEnv.t),
  exportedEnvOverride: option(ExportedEnv.Override.t),
  buildEnv: option(BuildEnv.t),
  buildEnvOverride: option(BuildEnv.Override.t),
};

type install = {
  dependencies: option(NpmFormula.Override.t),
  devDependencies: option(NpmFormula.Override.t),
  [@default None]
  resolutions: option(StringMap.t(Resolution.resolution)),
};

let build: t => RunAsync.t(option(build));
let install: t => RunAsync.t(option(install));

let ofJson: Json.t => t;
let ofDist: (Json.t, Dist.t) => t;
