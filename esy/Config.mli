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

module Value : sig
  type t

  val v : string -> t

  val toString : config -> t -> string
  val ofString : config -> string -> t

  val show : t -> string
  val pp : Format.formatter -> t -> unit
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder
end

module Path : sig
  type t

  val v : string -> t

  val sandbox : t
  val store : t
  val localStore : t

  val (/) : t -> string -> t

  val ofPath : config -> Path.t -> t
  val toPath : config -> t -> Path.t

  val show : t -> string
  val toValue : t -> Value.t
  val pp : Format.formatter -> t -> unit
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder
end
