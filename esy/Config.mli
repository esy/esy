(** Configuration *)

type t = private {
  spec : EsyInstall.SandboxSpec.t;
  buildCfg : EsyBuildPackage.Config.t;
}

val make :
  prefixPath:Fpath.t option
  -> spec:EsyInstall.SandboxSpec.t
  -> unit
  -> t Run.t
