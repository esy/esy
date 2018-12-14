(**
 * This represents esy project.
 *
 * Project can be in multiple states and in multiple configurations.
 *)

open Esy
open EsyInstall

type 'solved project = {
  projcfg : ProjectConfig.t;
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
 * Project without configured workflow.
 *
 * This kind of a project is used by low level plumbing esy commands.
 *)
module WithoutWorkflow : sig

  type t = unit fetched solved project

  val make : ProjectConfig.t -> (t * FileInfo.t list) Run.t Lwt.t

  val term : Fpath.t option -> t Cmdliner.Term.t
  val promiseTerm : Fpath.t option -> t RunAsync.t Cmdliner.Term.t
end

(**
 * Project configured with a default workflow.
 *
 * Most esy commands use this kind of a project.
 *)
module WithWorkflow : sig

  type t = configured fetched solved project

  and configured = {
    workflow : Workflow.t;
    scripts : Scripts.t;
    plan : BuildSandbox.Plan.t;
    root : BuildSandbox.Task.t;
  }

  val make : ProjectConfig.t -> (t * FileInfo.t list) Run.t Lwt.t

  val term : Fpath.t option -> t Cmdliner.Term.t
  val promiseTerm : Fpath.t option -> t RunAsync.t Cmdliner.Term.t
end
