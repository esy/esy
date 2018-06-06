/**

  This module represents the dependency graph with concrete package versions
  which was solved by solver and is ready to be fetched by the package fetcher.


  */
module Source = {
  [@deriving yojson]
  type t = {
    src,
    opam: option(opamFile),
  }
  and src =
    /* url & checksum */
    | Archive(string, string)
    /* url & commit */
    | GitSource(string, string)
    | GithubSource(string, string, string)
    | File(string)
    | NoSource
  and opamFile = (Json.t, list((Path.t, string)), list(string));
};

module Version = {
  [@deriving (ord, yojson)]
  type t =
    /* TODO: Github's ref shouldn't be optional */
    | Github(string, string, option(string))
    | Npm(NpmVersion.Version.t)
    | Opam(OpamVersion.Version.t)
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
    | Npm(t) => "npm-" ++ NpmVersion.Version.toString(t)
    | Opam(v) => "opam-" ++ OpamVersion.Version.toString(v)
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
    | Npm(v) => NpmVersion.Version.toString(v)
    | Opam(t) => OpamVersion.Version.toString(t)
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
};

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
