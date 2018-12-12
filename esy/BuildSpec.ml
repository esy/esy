module Package = EsyI.Solution.Package

type t = {
  build : build;
  buildLink : build option;
  buildRoot : build option;
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

let classify spec solution pkg =
  let root = EsyI.Solution.root solution in
  let isRoot = Package.compare root pkg = 0 in
  let kind =
    if isRoot
    then `Root
    else match pkg.Package.source with
    | Link _ -> `Link
    | Install _ -> `All
  in
  match kind, spec.buildRoot, spec.buildLink with
  | `All,     _,              _               -> spec.build

  | `Link,    _,              None            -> spec.build
  | `Link,    _,              Some buildLink  -> buildLink

  | `Root,    Some buildRoot, _               -> buildRoot
  | `Root,    None,           Some buildLink  -> buildLink
  | `Root,    None,           None            -> spec.build
