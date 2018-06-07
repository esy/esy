/**

  This module represents the dependency graph with concrete package versions
  which was solved by solver and is ready to be fetched by the package fetcher.


  */
[@deriving yojson]
type t = {
  root,
  buildDependencies: list(root),
}
and root = {
  pkg,
  bag: list(pkg),
}
and pkg = {
  name: string,
  version: PackageInfo.Version.t,
  source: PackageInfo.Source.t,
  opam: [@default None] option(PackageInfo.OpamInfo.t),
};

let ofFile = (filename: Path.t) =>
  RunAsync.Syntax.(
    {
      let%bind json = Fs.readJsonFile(filename);
      switch (of_yojson(json)) {
      | Error(err) =>
        let msg = Printf.sprintf("Invalid lockfile: %s", err);
        error(msg);
      | Ok(a) => return(a)
      };
    }
  );

/* TODO: use RunAsync */
let toFile = (filename: Path.t, solution: t) => {
  let json = to_yojson(solution);
  Fs.writeJsonFile(~json, filename);
};
