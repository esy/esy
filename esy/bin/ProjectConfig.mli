(**
 * This represents esy project config.
 *
 * If command line application was able to create it then it found a valid esy
 * project.
 *)

open EsyInstall
open Esy

type t = {
  mainprg : string;
  cfg : Config.t;
  workflow : Workflow.t;
  buildModeForDev : BuildSpec.plan;
  buildModeForRelease : BuildSpec.plan;
  spec : SandboxSpec.t;
  solveSandbox : EsySolve.Sandbox.t;
  installSandbox : EsyInstall.Sandbox.t;
}

val promiseTerm : Fpath.t option -> t RunAsync.t Cmdliner.Term.t

val term : Fpath.t option -> t Cmdliner.Term.t
