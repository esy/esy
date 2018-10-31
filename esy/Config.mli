(** Configuration *)

type t = {
  esyVersion : string;
  spec : EsyInstall.SandboxSpec.t;
  installCfg : EsyInstall.Config.t;
  buildCfg : EsyBuildPackage.Config.t;
  esyBuildPackageCmd : Cmd.t;
}

val defaultPrefixPath : Path.t

val make :
  installCfg:EsyInstall.Config.t
  -> esyVersion:string
  -> prefixPath:Fpath.t option
  -> esyBuildPackageCmd:Cmd.t
  -> spec:EsyInstall.SandboxSpec.t
  -> unit
  -> t Run.t
