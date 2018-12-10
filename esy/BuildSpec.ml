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

let classify spec pkg =
  match pkg.Package.source, spec.buildLinked with
  | Install _, _ -> spec.buildAll
  | Link _, None -> spec.buildAll
  | Link _, Some buildLinked -> buildLinked
