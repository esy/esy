open EsyPackageConfig

(** Sandbox *)

type t = {
  (** Configuration. *)
  cfg : Config.t;

  spec : EsyInstall.SandboxSpec.t;

  (** Root package. *)
  root : InstallManifest.t;

  (** A set of resolutions. *)
  resolutions : Resolutions.t;

  (** Resolver associated with a sandbox. *)
  resolver : Resolver.t;
}

val make : cfg:Config.t -> EsyInstall.SandboxSpec.t -> t RunAsync.t
