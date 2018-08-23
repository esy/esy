(** Configuration *)

type t = {
  buildConfig : EsyBuildPackage.Config.t;
  esyVersion : string;
  prefixPath : Path.t;
  fastreplacestringCommand : Cmd.t;
  esyBuildPackageCommand : Cmd.t;
}

type config = t

val defaultPrefixPath : Path.t

val create :
  fastreplacestringCommand:Cmd.t
  -> esyBuildPackageCommand:Cmd.t
  -> esyVersion:string
  -> prefixPath:Fpath.t option
  -> Fpath.t
  -> t Run.t

val init : t -> unit RunAsync.t

module Value : module type of EsyBuildPackage.Config.Value
module Environment : module type of EsyBuildPackage.Config.Environment
module Path : module type of EsyBuildPackage.Config.Path
