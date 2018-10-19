(** Configuration *)

type t = {
  esyVersion : string;
  spec : EsyInstall.SandboxSpec.t;
  installCfg : EsyInstall.Config.t;
  buildCfg : EsyBuildPackage.Config.t;
  fastreplacestringCmd : Cmd.t;
  esyBuildPackageCmd : Cmd.t;
}

val defaultPrefixPath : Path.t

val make :
  installCfg:EsyInstall.Config.t
  -> esyVersion:string
  -> prefixPath:Fpath.t option
  -> fastreplacestringCmd:Cmd.t
  -> esyBuildPackageCmd:Cmd.t
  -> spec:EsyInstall.SandboxSpec.t
  -> unit
  -> t Run.t
