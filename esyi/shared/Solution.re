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
    | Npm(Types.npmConcrete)
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
    | Npm(t) => "npm-" ++ Types.viewNpmConcrete(t)
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
    | Npm(t) => Types.viewNpmConcrete(t)
    | Opam(t) => Types.viewOpamConcrete(t)
    /* TODO hash the file path or something */
    | LocalPath(_s) => "local-file-0000"
    };
};

[@deriving yojson]
type t = {
  root: rootPackage,
  buildDependencies: list(rootPackage),
}
and rootPackage = {
  pkg,
  bag: list(pkg),
}
and pkg = {
  name: string,
  version: Version.t,
  source: Source.t,
  requested: Types.depsByKind,
  runtime: list(resolved),
  build: list(resolved),
}
and resolved = (string, Types.requestedDep, Version.t);

/* TODO: use RunAsync */
let ofFile = (filename: Path.t) => {
  let json = Yojson.Safe.from_file(Path.toString(filename));
  switch (of_yojson(json)) {
  | Error(_a) => failwith("Bad lockfile")
  | Ok(a) => a
  };
};

/* TODO: use RunAsync */
let toFile = (filename: Path.t, solution: t) => {
  let json = to_yojson(solution);
  let chan = open_out(Path.toString(filename));
  Yojson.Safe.pretty_to_channel(chan, json);
  close_out(chan);
};
