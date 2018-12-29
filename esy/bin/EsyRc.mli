type t = {
  prefixPath : Path.t option;
  buildModeForDev : Esy.BuildSpec.plan;
  buildModeForRelease : Esy.BuildSpec.plan;
  workflow : Workflow.t;
}

val ofPath : Fpath.t -> t RunAsync.t
