(** Configuration *)

type t = {
  esyVersion : string;
  prefixPath : Path.t;
  storePath : Path.t;
  installCfg : EsyInstall.Config.t;
}

val defaultPrefixPath : Path.t

val make :
  installCfg:EsyInstall.Config.t
  -> esyVersion:string
  -> prefixPath:Fpath.t option
  -> unit
  -> t Run.t
