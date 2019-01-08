(**
 * This represents esy project config.
 *
 * If command line application was able to create it then it found a valid esy
 * project.
 *)

type t = {
  mainprg : string;
  esyVersion : string;
  cfg : EsyBuildPackage.Config.t;
  spec : EsyInstall.SandboxSpec.t;

  prefixPath : Path.t option;
  cachePath : Path.t option;
  cacheTarballsPath : Path.t option;
  opamRepository : EsySolve.Config.checkoutCfg option;
  esyOpamOverride : EsySolve.Config.checkoutCfg option;
  npmRegistry : string option;
  solveTimeout : float option;
  skipRepositoryUpdate : bool;
  solveCudfCommand : Cmd.t option;
}

val show : t -> string
val pp : t Fmt.t
val to_yojson : t -> Json.t

val promiseTerm : Fpath.t option -> t RunAsync.t Cmdliner.Term.t

val term : Fpath.t option -> t Cmdliner.Term.t
