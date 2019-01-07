(** Configuration *)

type t = private {
  spec : EsyInstall.SandboxSpec.t;
  installCfg : EsyInstall.Config.t;
  buildCfg : EsyBuildPackage.Config.t;
}

val defaultPrefixPath : Path.t

val make :
  installCfg:EsyInstall.Config.t
  -> prefixPath:Fpath.t option
  -> spec:EsyInstall.SandboxSpec.t
  -> unit
  -> t Run.t
