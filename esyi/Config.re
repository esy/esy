module Path = EsyLib.Path;
module Option = EsyLib.Option;

type t = {
  basePath: Path.t,
  lockfilePath: Path.t,
  /* TODO: Figure out if we need to keep tarballs, maybe packageCacheDir will
   * suffice - at least yarn does only it. */
  tarballCachePath: Path.t,
  esyOpamOverridePath: Path.t,
  opamRepositoryPath: Path.t,
  npmRegistry: string,
};

let userDirectory = () => {
  let uid = Unix.getuid();
  let home = Unix.getpwuid(uid).Unix.pw_dir;
  /* TODO: fallback to $HOME here */
  /* TODO: make it return result instead. */
  Path.v(home);
};

let make = (~npmRegistry=?, ~cachePath=?, basePath) => {
  let cachePath =
    Option.orDefault(Path.(userDirectory() / ".esy" / "esyi"), cachePath);

  let tarballCachePath = Path.(cachePath / "tarballs");
  Files.mkdirp(Path.to_string(tarballCachePath));

  /* XXX: Those two shouldn't be created here as code in ensureGitRepo relies on
   * their existence to perform either clone or update, consider refactoring it.
   */
  let opamRepositoryPath = Path.(cachePath / "opam-repository");
  let esyOpamOverridePath = Path.(cachePath / "esy-opam-override");

  let npmRegistry =
    Option.orDefault("http://registry.npmjs.org/", npmRegistry);

  {
    basePath,
    lockfilePath: Path.(basePath / "esyi.lock.json"),
    tarballCachePath,
    opamRepositoryPath,
    esyOpamOverridePath,
    npmRegistry,
  };
};
