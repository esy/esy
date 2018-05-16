
[@deriving yojson]
type realVersion = [
  | `Github(string, string, option(string))
  | `Npm(Types.npmConcrete)
  | `Opam(Types.opamConcrete)
  | `Git(string)
  | `File(string)
];

let viewRealVersion: realVersion => string = v => switch v {
| `Github(user, repo, ref) => "github-" ++ user ++ "__" ++ repo ++ (switch ref { | Some(x) => "__" ++ x | None => ""})
| `Git(s) => "git-" ++ s
| `Npm(t) => "npm-" ++ Types.viewNpmConcrete(t)
| `Opam(t) => "opam-" ++ Types.viewOpamConcrete(t)
| `File(s) => "local-file"
};

let plainVersionNumber = v => switch v {
| `Github(user, repo, ref) => user ++ "__" ++ repo ++ (switch ref { | Some(x) => "__" ++ x | None => ""})
| `Git(s) => s
| `Npm(t) => Types.viewNpmConcrete(t)
| `Opam(t) => Types.viewOpamConcrete(t)
/* TODO hash the file path or something */
| `File(s) => "local-file-0000"
};