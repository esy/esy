module Path = EsyLib.Path;

[@deriving (ord, yojson)]
type realVersion =
  | Github(string, string, option(string))
  | Npm(Types.npmConcrete)
  | Opam(Types.opamConcrete)
  | Git(string)
  | LocalPath(Path.t);

let viewRealVersion: realVersion => string =
  v =>
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

let plainVersionNumber = v =>
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
