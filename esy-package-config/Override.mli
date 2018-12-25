type t =
  | OfJson of {json : Json.t;}
  | OfDist of {dist : Dist.t; json : Json.t;}
  | OfOpamOverride of {
      path : Path.t;
      json : Json.t;
    }

val pp : t Fmt.t

type build = {
  buildType : BuildType.t option;
  build : CommandList.t option;
  install : CommandList.t option;
  exportedEnv: ExportedEnv.t option;
  exportedEnvOverride: ExportedEnv.Override.t option;
  buildEnv: BuildEnv.t option;
  buildEnvOverride: BuildEnv.Override.t option;
}

type install = {
  dependencies : NpmFormula.Override.t option;
  devDependencies : NpmFormula.Override.t option;
  resolutions : Resolution.resolution StringMap.t option [@default None];
}

val build : t -> build option RunAsync.t
val install : t -> install option RunAsync.t

val ofJson : Json.t -> t
val ofDist : Json.t -> Dist.t -> t
