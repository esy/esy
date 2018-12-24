(** Configuration *)

type t = private {
  esyVersion : string;
  spec : EsyInstall.SandboxSpec.t;
  installCfg : EsyInstall.Config.t;
  buildCfg : EsyBuildPackage.Config.t;
}

val defaultPrefixPath : Path.t

val make :
  installCfg:EsyInstall.Config.t
  -> esyVersion:string
  -> prefixPath:Fpath.t option
  -> spec:EsyInstall.SandboxSpec.t
  -> unit
  -> t Run.t
