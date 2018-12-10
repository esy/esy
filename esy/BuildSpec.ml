module Package = EsyInstall.Solution.Package

type t = {
  buildLinked : build option;
  buildAll : build;
}

and build = {
  mode : mode;
  deps : DepSpec.t;
}

and mode =
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

let classify spec pkg =
  match pkg.Package.source, spec.buildLinked with
  | Install _, _ -> spec.buildAll
  | Link _, None -> spec.buildAll
  | Link _, Some buildLinked -> buildLinked
