type t =
  | OfJson of {json : Json.t;}
  | OfDist of {dist : Dist.t; json : Json.t;}
  | OfOpamOverride of {
      path : Path.t;
      json : Json.t;
    }

module BuildType = struct
  include EsyLib.BuildType
  include EsyLib.BuildType.AsInPackageJson
end

type build = {
  buildType : BuildType.t option [@default None] [@key "buildsInSource"];
  build : PackageConfig.CommandList.t option [@default None];
  install : PackageConfig.CommandList.t option [@default None];
  exportedEnv: PackageConfig.ExportedEnv.t option [@default None];
  exportedEnvOverride: PackageConfig.ExportedEnvOverride.t option [@default None];
  buildEnv: PackageConfig.Env.t option [@default None];
  buildEnvOverride: PackageConfig.EnvOverride.t option [@default None];
} [@@deriving of_yojson { strict = false }]

type install = {
  dependencies : PackageConfig.NpmFormulaOverride.t option [@default None];
  devDependencies : PackageConfig.NpmFormulaOverride.t option [@default None];
  resolutions : PackageConfig.Resolution.resolution StringMap.t option [@default None];
} [@@deriving of_yojson { strict = false }]

let pp fmt = function
  | OfJson _ -> Fmt.unit "<inline override>" fmt ()
  | OfDist {dist; json = _;} -> Fmt.pf fmt "override:%a" Dist.pp dist
  | OfOpamOverride info -> Fmt.pf fmt "opam-override:%a" Path.pp info.path

let json override =
  let open RunAsync.Syntax in
  match override with
  | OfJson info -> return info.json
  | OfDist info -> return info.json
  | OfOpamOverride info -> return info.json

let build override =
  let open RunAsync.Syntax in
  let%bind json = json override in
  let%bind override = RunAsync.ofStringError (build_of_yojson json) in
  return (Some override)

let install override =
  let open RunAsync.Syntax in
  let%bind json = json override in
  let%bind override = RunAsync.ofStringError (install_of_yojson json) in
  return (Some override)

let ofJson json = OfJson {json;}
let ofDist json dist = OfDist {json; dist;}
