let githubFileUrl = (user, repo, ref, file) =>
  "https://raw.githubusercontent.com/"
  ++ user
  ++ "/"
  ++ repo
  ++ "/"
  ++ Option.orDefault(~default="master", ref)
  ++ "/"
  ++ file;

let getManifest = (name, user, repo, ref) => {
  let getFile = name =>
    Lwt_main.run(Curl.get(githubFileUrl(user, repo, ref, name)));
  switch (getFile("esy.json")) {
  | Ok(text) => Manifest.PackageJson(Yojson.Safe.from_string(text))
  | Error(_) =>
    switch (getFile("package.json")) {
    | Ok(text) => Manifest.PackageJson(Yojson.Safe.from_string(text))
    | Error(_) =>
      switch (getFile(name ++ ".opam")) {
      | Ok(_text) => failwith("No opam parsing yet for github repos")
      | Error(_) =>
        switch (getFile("opam")) {
        | Ok(_text) => failwith("No opam parsing yet for github repos")
        | Error(_) => failwith("No manifest found in github repo")
        }
      }
    }
  };
};
