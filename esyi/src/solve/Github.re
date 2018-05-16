
open Shared.Infix;

let githubFileUrl = (user, repo, ref, file) => {
  "https://raw.githubusercontent.com/" ++ user ++"/" ++ repo ++ "/" ++ (ref |? "master") ++ "/" ++ file
};

let getManifest = (name, user, repo, ref) => {
  let getFile = name => Shared.Wget.get(githubFileUrl(user, repo, ref, name));
  switch (getFile("esy.json")) {
    | Some(text) => `PackageJson(Yojson.Basic.from_string(text))
    | None => switch (getFile("package.json")) {
      | Some(text) => `PackageJson(Yojson.Basic.from_string(text))
      | None => switch (getFile(name ++ ".opam")) {
        | Some(text) => failwith("No opam parsing yet for github repos")
        | None => switch (getFile("opam")) {
          | Some(text) => failwith("No opam parsing yet for github repos")
          | None => failwith("No manifest found in github repo")
        }
      }
    }
  }
};