open EsyInstall

type t =
  | ByPkgSpec of PkgSpec.t
  | ByPath of Path.t

val root : t

val pp : t Fmt.t
val parse : string -> (t, string) result
val conv : t Cmdliner.Arg.conv
