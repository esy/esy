(** Configuration *)

type t = {
  esyVersion : string;
  spec : EsyI.SandboxSpec.t;
  installCfg : EsyI.Config.t;
  buildCfg : EsyBuildPackage.Config.t;
}

val defaultPrefixPath : Path.t

val make :
  installCfg:EsyI.Config.t
  -> esyVersion:string
  -> prefixPath:Fpath.t option
  -> spec:EsyI.SandboxSpec.t
  -> unit
  -> t Run.t
