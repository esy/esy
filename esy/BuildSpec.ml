open EsyPackageConfig
module Package = EsyInstall.Package

type t = {
  buildAll : DepSpec.t;
  buildDev : DepSpec.t option;
}

type mode =
  | Build
  | BuildDev
  | BuildDevForce

let show_mode = function
  | Build -> "build"
  | BuildDev -> "buildDev"
  | BuildDevForce -> "buildDevForce"

let pp_mode fmt mode =
  Fmt.string fmt (show_mode mode)

let mode_to_yojson = function
  | Build -> `String "build"
  | BuildDev -> `String "buildDev"
  | BuildDevForce -> `String "buildDevForce"

let mode_of_yojson = function
  | `String "build" -> Ok Build
  | `String "buildDev" -> Ok BuildDev
  | _json -> Result.errorf {|invalid BuildSpec.mode: expected "build" or "buildDev"|}

let classify spec mode pkg (build : BuildManifest.t) =
  match pkg.Package.source, mode, build.buildDev with
  | Link {kind = LinkDev; _}, BuildDevForce, _ ->
    let depspec = Option.orDefault ~default:spec.buildAll spec.buildDev in
    BuildDev, depspec, build.build
  | Link {kind = LinkDev; _}, BuildDev, Some buildDev ->
    let depspec = Option.orDefault ~default:spec.buildAll spec.buildDev in
    let commands = BuildManifest.EsyCommands buildDev in
    BuildDev, depspec, commands
  | Link {kind = LinkDev; _}, BuildDev, None
  | Link {kind = LinkDev; _}, Build, _
  | Link {kind = LinkRegular; _}, _, _
  | Install _, _, _ ->
    Build, spec.buildAll, build.build
