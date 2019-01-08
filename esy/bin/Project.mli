(**
 * This represents esy project.
 *
 * Project can be in multiple states and in multiple configurations.
 *)

open Esy
open EsyInstall

type project = {
  projcfg : ProjectConfig.t;
  spec : SandboxSpec.t;
  workflow : Workflow.t;
  solveSandbox : EsySolve.Sandbox.t;
  installSandbox : EsyInstall.Sandbox.t;
  scripts : Scripts.t;
  solved : solved Run.t;
}

and solved = {
  solution : Solution.t;
  fetched : fetched Run.t;
}

and fetched = {
  installation : Installation.t;
  sandbox : BuildSandbox.t;
  configured : configured Run.t;
}

and configured = {
  planForDev : BuildSandbox.Plan.t;
  root : BuildSandbox.Task.t;
}

type t = project

val solved : project -> solved RunAsync.t
val fetched : project -> fetched RunAsync.t
val configured : project -> configured RunAsync.t

val make : ProjectConfig.t -> EsyInstall.SandboxSpec.t -> (project * FileInfo.t list) Run.t Lwt.t

val plan : BuildSpec.mode -> project -> BuildSandbox.Plan.t RunAsync.t

val ocaml : project -> Fpath.t RunAsync.t
(** Built and installed ocaml package resolved in a project env. *)

val ocamlfind : project -> Fpath.t RunAsync.t
(** Build & installed ocamlfind package resolved in a project env. *)

val term : Fpath.t option -> project Cmdliner.Term.t
val promiseTerm : Fpath.t option -> project RunAsync.t Cmdliner.Term.t

val withPackage :
  project
  -> PkgArg.t
  -> (Package.t -> 'a Run.t Lwt.t)
  -> 'a RunAsync.t

val buildDependencies :
  buildLinked:bool
  -> project
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
  -> project
  -> EnvSpec.t
  -> BuildSpec.mode
  -> Package.t
  -> Cmd.t
  -> unit RunAsync.t

val printEnv :
  ?name:string
  -> project
  -> EnvSpec.t
  -> BuildSpec.mode
  -> bool
  -> PkgArg.t
  -> unit
  -> unit RunAsync.t
