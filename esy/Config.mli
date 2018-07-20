(** Configuration *)

type t = {
  esyVersion : string;
  sandboxPath : Path.t;
  prefixPath : Path.t;
  storePath : Path.t;
  localStorePath : Path.t;
  fastreplacestringCommand : Cmd.t;
  esyBuildPackageCommand : Cmd.t;
  esyInstallJsCommand : string;
}

type config = t

val defaultPrefixPath : Path.t

val create :
  fastreplacestringCommand:Cmd.t
  -> esyBuildPackageCommand:Cmd.t
  -> esyInstallJsCommand:string
  -> esyVersion:string
  -> prefixPath:Fpath.t option
  -> Fpath.t
  -> t RunAsync.t

module ConfigPath : sig
  type t
  type ctx = config
  val ( / ) : t -> string -> t
  val ofPath : ctx -> Fpath.t -> t
  val toPath : ctx -> t -> Fpath.t
  val toString : t -> string
  val pp : Format.formatter -> t -> unit
  val to_yojson : t -> Yojson.Safe.json
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val sandbox : t
  val store : t
  val localStore : t
end
