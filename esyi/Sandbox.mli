(** Sandbox *)

type t = {
  (** Configuration. *)
  cfg : Config.t;

  (** Path to sandbox root. *)
  path : Path.t;

  (** Root package. *)
  root : Package.t;

  (**
   * A set of dependencies to be installed for the sandbox.
   *
   * Such dependencies are different than of root.dependencies as sandbox
   * aggregates both regular dependencies and devDependencies.
   *)
  dependencies : Package.Dependencies.t;

  (** A set of resolutions. *)
  resolutions : Package.Resolutions.t;

  (** OCaml version request defined for the sandbox. *)
  ocamlReq : Package.Req.t option;

  (** Type of configuration origin of the sandbox. *)
  origin : origin;
}

(** Types of configuration files containing their paths. *)
and origin =
  | Esy of Path.t
  | Opam of Path.t
  | AggregatedOpam of Path.t list

(** Read sandbox out of directory given the config. *)
val ofDir : cfg:Config.t -> Path.t -> t RunAsync.t
