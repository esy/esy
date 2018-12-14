open EsyInstall

type t =
  | ByPkgSpec of PkgSpec.t
  | ByPath of Path.t

let pp fmt = function
  | ByPkgSpec spec -> PkgSpec.pp fmt spec
  | ByPath path -> Path.pp fmt path

let parse v =
  let open Result.Syntax in
  if Sys.file_exists v && not (Sys.is_directory v)
  then return (ByPath (Path.v v))
  else
    let%map pkgspec = PkgSpec.parse v in
    ByPkgSpec pkgspec

let root = ByPkgSpec Root

let conv =
  let open Cmdliner in
  let parse v = Rresult.R.error_to_msg ~pp_error:Fmt.string (parse v) in
  Arg.conv ~docv:"PACKAGE" (parse, pp)

