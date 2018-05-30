type t = {
  basePath: Path.t,
  lockfilePath: Path.t,
  tarballCachePath: Path.t,
  esyOpamOverridePath: Path.t,
  opamRepositoryPath: Path.t,
  npmRegistry: string,
};

let make = (~npmRegistry=?, ~cachePath=?, basePath) =>
  RunAsync.Syntax.(
    {
      let%bind cachePath =
        RunAsync.ofRun(
          Run.Syntax.(
            switch (cachePath) {
            | Some(cachePath) => return(cachePath)
            | None =>
              let%bind userDir = Path.user();
              return(Path.(userDir / ".esy" / "esyi"));
            }
          ),
        );

      let tarballCachePath = Path.(cachePath / "tarballs");
      let%bind () = Fs.createDirectory(tarballCachePath);

      /* Those two shouldn't be created here as code in ensureGitRepo relies on
       * their existence to perform either clone or update, consider refactoring it.
       */
      let opamRepositoryPath = Path.(cachePath / "opam-repository");
      let esyOpamOverridePath = Path.(cachePath / "esy-opam-override");

      let npmRegistry =
        Option.orDefault("http://registry.npmjs.org/", npmRegistry);

      return({
        basePath,
        lockfilePath: Path.(basePath / "esyi.lock.json"),
        tarballCachePath,
        opamRepositoryPath,
        esyOpamOverridePath,
        npmRegistry,
      });
    }
  );
