(** Configuration *)

type t = {
  esyVersion : string;
  spec : EsyInstall.SandboxSpec.t;
  installCfg : EsySolve.Config.t;
  buildCfg : EsyBuildPackage.Config.t;
}

val defaultPrefixPath : Path.t

val make :
  installCfg:EsySolve.Config.t
  -> esyVersion:string
  -> prefixPath:Fpath.t option
  -> spec:EsyInstall.SandboxSpec.t
  -> unit
  -> t Run.t
