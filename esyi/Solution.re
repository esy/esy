/**

  This module represents the dependency graph with concrete package versions
  which was solved by solver and is ready to be fetched by the package fetcher.


  */
module Path = EsyLib.Path;

module Source = {
  [@deriving yojson]
  type t = (info, option(Types.opamFile))
  and info =
    /* url & checksum */
    | Archive(string, string)
    /* url & commit */
    | GitSource(string, string)
    | GithubSource(string, string, string)
    | File(string)
    | NoSource;
};

module Version = {
  [@deriving (ord, yojson)]
  type t =
    /* TODO: Github's ref shouldn't be optional */
    | Github(string, string, option(string))
    | Npm(NpmVersion.t)
    | Opam(Types.opamConcrete)
    | Git(string)
    | LocalPath(Path.t);

  let toString = v =>
    switch (v) {
    | Github(user, repo, ref) =>
      "github-"
      ++ user
      ++ "__"
      ++ repo
      ++ (
        switch (ref) {
        | Some(x) => "__" ++ x
        | None => ""
        }
      )
    | Git(s) => "git-" ++ s
    | Npm(t) => "npm-" ++ NpmVersion.toString(t)
    | Opam(t) => "opam-" ++ Types.viewOpamConcrete(t)
    | LocalPath(_s) => "local-file"
    };

  let toNpmVersion = v =>
    switch (v) {
    | Github(user, repo, ref) =>
      user
      ++ "__"
      ++ repo
      ++ (
        switch (ref) {
        | Some(x) => "__" ++ x
        | None => ""
        }
      )
    | Git(s) => s
    | Npm(v) => NpmVersion.toString(v)
    | Opam(t) => Types.viewOpamConcrete(t)
    /* TODO hash the file path or something */
    | LocalPath(_s) => "local-file-0000"
    };
};

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
  version: Version.t,
  source: Source.t,
  requested: Types.depsByKind,
  runtime: list(resolution),
  build: list(resolution),
}
and resolution = (string, Types.requestedDep, Version.t);

let ofFile = (filename: Path.t) =>
  RunAsync.Syntax.(
    {
      let%bind json = Fs.readJsonFile(filename);
      switch (of_yojson(json)) {
      | Error(_a) => error("Bad lockfile")
      | Ok(a) => return(a)
      };
    }
  );

/* TODO: use RunAsync */
let toFile = (filename: Path.t, solution: t) => {
  let json = to_yojson(solution);
  Fs.writeJsonFile(~json, filename);
};
