open EsyPackageConfig
module Package = EsyInstall.Package

type t = EsyInstall.Solution.Spec.t = {
  all : EsyInstall.Solution.DepSpec.t;
  dev : EsyInstall.Solution.DepSpec.t;
}

type mode =
  | Build
  | BuildDev

let show_mode = function
  | Build -> "build"
  | BuildDev -> "buildDev"

let pp_mode fmt mode =
  Fmt.string fmt (show_mode mode)

let mode_to_yojson = function
  | Build -> `String "build"
  | BuildDev -> `String "buildDev"

let mode_of_yojson = function
  | `String "build" -> Ok Build
  | `String "buildDev" -> Ok BuildDev
  | _json -> Result.errorf {|invalid BuildSpec.mode: expected "build" or "buildDev"|}

let classify spec mode pkg (build : BuildManifest.t) =
  match pkg.Package.source, mode with
  | Link {kind = LinkDev; _}, BuildDev ->
    let commands =
      match build.buildDev with
      | Some buildDev -> BuildManifest.EsyCommands buildDev
      | None -> build.build
    in
    BuildDev, spec.dev, commands
  | Link {kind = LinkDev; _}, Build
  | Link {kind = LinkRegular; _}, _
  | Install _, _ ->
    Build, spec.all, build.build
