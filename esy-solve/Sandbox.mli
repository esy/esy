open EsyPackageConfig

(** Sandbox *)

type t = {
  (** Configuration. *)
  cfg : Config.t;

  spec : EsyInstall.SandboxSpec.t;

  (** Root package. *)
  root : InstallManifest.t;

  (**
   * A set of dependencies to be installed for the sandbox.
   *
   * Such dependencies are different than of root.dependencies as sandbox
   * aggregates both regular dependencies and devDependencies.
   *)
  dependencies : InstallManifest.Dependencies.t;

  (** A set of resolutions. *)
  resolutions : Resolutions.t;

  (** OCaml version request defined for the sandbox. *)
  ocamlReq : Req.t option;

  (** Resolver associated with a sandbox. *)
  resolver : Resolver.t;
}

val make : cfg:Config.t -> EsyInstall.SandboxSpec.t -> t RunAsync.t
