(**
 * This represents esy project.
 *
 * Project can be in multiple states and in multiple configurations.
 *)

open Esy
open EsyInstall

type 'solved project = {
  projcfg : ProjectConfig.t;
  scripts : Scripts.t;
  solved : 'solved Run.t;
}

and 'fetched solved = {
  solution : Solution.t;
  fetched : 'fetched Run.t;
}

and 'configured fetched = {
  installation : Installation.t;
  sandbox : BuildSandbox.t;
  configured : 'configured Run.t;
}

val solved : 'a project -> 'a RunAsync.t
val fetched : 'a solved project -> 'a RunAsync.t
val configured : 'a fetched solved project -> 'a RunAsync.t

(**
 * Project configured with a default workflow.
 *
 * Most esy commands use this kind of a project.
 *)
module WithWorkflow : sig

  type t = configured fetched solved project

  and configured = {
    workflow : Workflow.t;
    planForDev : BuildSandbox.Plan.t;
    root : BuildSandbox.Task.t;
  }

  val make : ProjectConfig.t -> (t * FileInfo.t list) Run.t Lwt.t

  val plan : BuildSpec.mode -> t -> BuildSandbox.Plan.t RunAsync.t

  val ocaml : t -> Fpath.t RunAsync.t
  (** Built and installed ocaml package resolved in a project env. *)

  val ocamlfind : t -> Fpath.t RunAsync.t
  (** Build & installed ocamlfind package resolved in a project env. *)

  val term : Fpath.t option -> t Cmdliner.Term.t
  val promiseTerm : Fpath.t option -> t RunAsync.t Cmdliner.Term.t

end

val withPackage :
  _ solved project
  -> PkgArg.t
  -> (Package.t -> 'a Run.t Lwt.t)
  -> 'a RunAsync.t

val buildDependencies :
  buildLinked:bool
  -> _ fetched solved project
  -> BuildSandbox.Plan.t
  -> Package.t
  -> unit RunAsync.t

val buildPackage :
  quiet:bool
  -> buildOnly:bool
  -> ProjectConfig.t
  -> BuildSandbox.t
  -> BuildSandbox.Plan.t
  -> Package.t
  -> unit RunAsync.t

val execCommand :
  checkIfDependenciesAreBuilt:bool
  -> buildLinked:bool
  -> _ fetched solved project
  -> EnvSpec.t
  -> BuildSpec.t
  -> BuildSpec.mode
  -> Package.t
  -> Cmd.t
  -> unit RunAsync.t

val printEnv :
  ?name:string
  -> _ fetched solved project
  -> EnvSpec.t
  -> BuildSpec.t
  -> BuildSpec.mode
  -> bool
  -> PkgArg.t
  -> unit
  -> unit RunAsync.t
