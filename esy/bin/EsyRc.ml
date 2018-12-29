type solvespec = EsySolve.SolveSpec.t = {
  solveRoot : EsySolve.DepSpec.t [@default Workflow.default.solvespec.solveRoot];
  solveLink : EsySolve.DepSpec.t [@default Workflow.default.solvespec.solveLink];
  solveAll : EsySolve.DepSpec.t [@default Workflow.default.solvespec.solveAll];
} [@@deriving of_yojson]

type buildspec = Esy.BuildSpec.t = {
  build : Esy.DepSpec.t [@default Workflow.default.buildspec.build];
  buildLink : Esy.DepSpec.t option [@default Workflow.default.buildspec.buildLink];
  buildRootForRelease : Esy.DepSpec.t option [@default Workflow.default.buildspec.buildRootForRelease];
  buildRootForDev : Esy.DepSpec.t option [@default Workflow.default.buildspec.buildRootForDev];
} [@@deriving of_yojson]

type buildModeForRelease = Esy.BuildSpec.plan = {
  all : Esy.BuildSpec.mode [@default Workflow.defaultPlanForRelease.all];
  link : Esy.BuildSpec.mode [@default Workflow.defaultPlanForRelease.link];
  root : Esy.BuildSpec.mode [@default Workflow.defaultPlanForRelease.root];
} [@@deriving of_yojson]

type buildModeForDev = Esy.BuildSpec.plan = {
  all : Esy.BuildSpec.mode [@default Workflow.defaultPlanForDev.all];
  link : Esy.BuildSpec.mode [@default Workflow.defaultPlanForDev.link];
  root : Esy.BuildSpec.mode [@default Workflow.defaultPlanForDev.root];
} [@@deriving of_yojson]

type workflow = Workflow.t = {
  solvespec : solvespec [@default Workflow.default.solvespec];
  buildspec : buildspec [@default Workflow.default.buildspec];
  execenvspec : Esy.EnvSpec.t [@default Workflow.default.execenvspec];
  commandenvspec : Esy.EnvSpec.t [@default Workflow.default.commandenvspec];
  buildenvspec : Esy.EnvSpec.t [@default Workflow.default.buildenvspec];
} [@@deriving of_yojson]

type t = {
  prefixPath : Path.t option [@default None];
  buildModeForDev : buildModeForDev  [@default Workflow.defaultPlanForDev];
  buildModeForRelease : buildModeForRelease [@default Workflow.defaultPlanForRelease];
  workflow : workflow [@default Workflow.default];
} [@@deriving of_yojson]

let empty = {
  prefixPath = None;
  workflow = Workflow.default;
  buildModeForDev = Workflow.defaultPlanForDev;
  buildModeForRelease = Workflow.defaultPlanForRelease;
}

let ofPath path =
  let open RunAsync.Syntax in

  let normalizePath p =
    if Path.isAbs p
    then p
    else Path.(normalize (path // p))
  in

  let ofFile filename =
    let%bind data = Fs.readFile filename in
    let%bind json =
      match Json.parse data with
      | Ok json -> return json
      | Error err ->
        errorf
          "expected %a to be a JSON file but got error: %a"
          Path.pp filename Run.ppError err
    in
    let%bind rc = RunAsync.ofStringError (of_yojson json) in
    let rc = {
      rc with
      prefixPath = Option.map ~f:normalizePath rc.prefixPath;
    } in
    return rc;
  in

  let filename = Path.(path / ".esyrc") in

  if%bind Fs.exists filename
  then ofFile filename
  else return empty
