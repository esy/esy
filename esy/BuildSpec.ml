open EsyPackageConfig
module Package = EsyInstall.Package

type t = {
  buildAll : DepSpec.t;
  buildDev : DepSpec.t option;
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

let classify spec mode pkg build =
  match pkg.Package.source, mode with
  | Link {kind = LinkDev; _}, BuildDev ->
    let depspec = Option.orDefault ~default:spec.buildAll spec.buildDev in
    let commands =
      match build.BuildManifest.buildDev with
      | None -> build.BuildManifest.build
      | Some cmds -> BuildManifest.EsyCommands cmds
    in
    depspec, commands
  | Link {kind = LinkDev; _}, Build
  | Link {kind = LinkRegular; _}, _
  | Install _, _ ->
    spec.buildAll, build.build
