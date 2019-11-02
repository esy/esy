/**
 * This represents esy project config.
 *
 * If command line application was able to create it then it found a valid esy
 * project.
 */;

type t = {
  mainprg: string,
  path: Path.t,
  esyVersion: string,
  spec: EsyInstall.SandboxSpec.t,
  prefixPath: option(Path.t),
  cacheTarballsPath: option(Path.t),
  opamRepository: option(EsySolve.Config.checkoutCfg),
  esyOpamOverride: option(EsySolve.Config.checkoutCfg),
  npmRegistry: option(string),
  solveTimeout: option(float),
  skipRepositoryUpdate: bool,
  solveCudfCommand: option(Cmd.t),
};

let storePath: t => Run.t(Path.t);

let show: t => string;
let pp: Fmt.t(t);
let to_yojson: t => Json.t;

let promiseTerm: Cmdliner.Term.t(RunAsync.t(t));
let term: Cmdliner.Term.t(t);
let multipleProjectConfigsTerm:
  Cmdliner.Arg.conv(EsyLib.Path.t) => Cmdliner.Term.t(list(t));
