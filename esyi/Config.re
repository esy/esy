type t = {
  basePath: Path.t,
  lockfilePath: Path.t,
  tarballCachePath: Path.t,
  esyOpamOverrideCheckoutPath: Path.t,
  opamRepositoryCheckoutPath: Path.t,
  npmRegistry: string,
};

let resolvedPrefix = "esyi5-";

let make =
    (
      ~npmRegistry=?,
      ~cachePath=?,
      ~opamRepositoryCheckoutPath=?,
      ~esyOpamOverrideCheckoutPath=?,
      basePath,
    ) =>
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
      let%bind () = Fs.createDir(tarballCachePath);

      /* Those two shouldn't be created here as code in ensureGitRepo relies on
       * their existence to perform either clone or update, consider refactoring it.
       */
      let opamRepositoryCheckoutPath =
        switch (opamRepositoryCheckoutPath) {
        | Some(opamRepositoryCheckoutPath) => opamRepositoryCheckoutPath
        | None => Path.(cachePath / "opam-repository")
        };
      let esyOpamOverrideCheckoutPath =
        switch (esyOpamOverrideCheckoutPath) {
        | Some(esyOpamOverrideCheckoutPath) => esyOpamOverrideCheckoutPath
        | None => Path.(cachePath / "esy-opam-override")
        };

      let npmRegistry =
        Option.orDefault(~default="http://registry.npmjs.org/", npmRegistry);

      return({
        basePath,
        lockfilePath: Path.(basePath / "esyi.lock.json"),
        tarballCachePath,
        opamRepositoryCheckoutPath,
        esyOpamOverrideCheckoutPath,
        npmRegistry,
      });
    }
  );
