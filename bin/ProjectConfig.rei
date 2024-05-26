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
  spec: EsyFetch.SandboxSpec.t,
  prefixPath: option(Path.t),
  ocamlPkgName: string,
  ocamlVersion: string,
  cacheTarballsPath: option(Path.t),
  fetchConcurrency: option(int),
  gitUsername: option(string),
  gitPassword: option(string),
  buildConcurrency: option(int),
  opamRepository: option(EsySolve.Config.checkoutCfg),
  esyOpamOverride: option(EsySolve.Config.checkoutCfg),
  opamRepositoryLocal: option(Path.t),
  opamRepositoryRemote: option(string),
  esyOpamOverrideLocal: option(Path.t),
  esyOpamOverrideRemote: option(string),
  npmRegistry: option(string),
  solveTimeout: option(float),
  skipRepositoryUpdate: bool,
  solveCudfCommand: option(Cmd.t),
  globalPathVariable: option(string),
};

let storePath: t => Run.t(Path.t);
let globalStorePrefixPath: t => Path.t;

let show: t => string;
let pp: Fmt.t(t);
let to_yojson: t => Json.t;

let promiseTerm: Esy_cmdliner.Term.t(RunAsync.t(t));
let term: Esy_cmdliner.Term.t(t);
let multipleProjectConfigsTerm:
  Esy_cmdliner.Arg.conv(EsyLib.Path.t) => Esy_cmdliner.Term.t(list(t));
