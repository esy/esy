open EsyPackageConfig
module Package = EsyInstall.Package

type t = {
  build : DepSpec.t;
  buildLink : DepSpec.t option;
  buildRootForRelease : DepSpec.t option;
  buildRootForDev : DepSpec.t option;
}

type mode =
  | Build
  | BuildDev

let pp_mode fmt = function
  | Build -> Fmt.string fmt "build"
  | BuildDev -> Fmt.string fmt "buildDev"

let show_mode = function
  | Build -> "build"
  | BuildDev -> "buildDev"

let mode_to_yojson = function
  | Build -> `String "build"
  | BuildDev -> `String "buildDev"

let mode_of_yojson = function
  | `String "build" -> Ok Build
  | `String "buildDev" -> Ok BuildDev
  | _json -> Result.errorf {|invalid BuildSpec.mode: expected "build" or "buildDev"|}

type plan = {
  all : mode;
  link : mode;
  root : mode;
}

let pp_plan fmt plan =
  Fmt.pf
    fmt "root=%a link=%a all=%a"
    pp_mode plan.root pp_mode plan.link pp_mode plan.all

let show_plan plan = Fmt.strf "%a" pp_plan plan

type build = {
  mode : mode;
  deps : DepSpec.t;
}

let classify spec plan solution pkg buildManifest =
  let root = EsyInstall.Solution.root solution in
  let isRoot = Package.compare root pkg = 0 in
  let commands = buildManifest.BuildManifest.build in
  let kind, mode =
    if isRoot
    then `Root, plan.root
    else match pkg.Package.source with
    | Link _ -> `Link, plan.link
    | Install _ -> `All, plan.all
  in
  (* force Build mode if no build commands is provided *)
  let mode, commands =
    match mode, buildManifest.BuildManifest.buildDev with
    | Build, _ -> mode, commands
    | BuildDev, None -> Build, commands
    | BuildDev, Some commands -> BuildDev, BuildManifest.EsyCommands commands
  in
  let build =
    match kind with
    | `All -> spec.build
    | `Link ->
      begin match spec.buildLink with
      | None -> spec.build
      | Some build -> build
      end
    | `Root ->
      begin match mode with
      | BuildDev ->
        begin match spec.buildRootForDev, spec.buildRootForRelease, spec.buildLink with
        | Some build, _,          _     -> build
        | None,       Some build, _     -> build
        | None,       None, Some build  -> build
        | None,       None,      None   -> spec.build
        end
      | Build ->
        begin match spec.buildRootForRelease, spec.buildLink with
        | Some build, _     -> build
        | None, Some build  -> build
        | None, None        -> spec.build
        end
      end
  in
  {deps = build; mode;}, commands
