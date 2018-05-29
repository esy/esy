open Shared;

module Path = EsyLib.Path;
module RunAsync = EsyLib.RunAsync;

let (/+) = Filename.concat;

let resolvedString = (name, version) =>
  Types.resolvedPrefix ++ name ++ "--" ++ Lockfile.viewRealVersion(version);

/** Hack to always cache the ocaml build :P */
let resolveString = (name, version) =>
  name == "ocaml" ?
    "esyi4-" ++ name ++ "--" ++ Lockfile.viewRealVersion(version) :
    resolvedString(name, version);

let addResolvedFieldToPackageJson = (filename, name, version) => {
  let json =
    switch (Yojson.Basic.from_file(filename)) {
    | `Assoc(items) => items
    | _ => failwith("bad json")
    };
  let raw =
    Yojson.Basic.pretty_to_string(
      `Assoc([
        ("_resolved", `String(resolvedString(name, version))),
        ...json,
      ]),
    );
  Files.writeFile(filename, raw)
  |> Files.expectSuccess("Could not write back package json");
};

let absname = (name, version) =>
  name ++ "__" ++ Lockfile.viewRealVersion(version);

let getSource = (dest, cache, name, version, source) =>
  switch (source) {
  | Solution.Source.Archive(url, _checksum) =>
    let safe = Str.global_replace(Str.regexp("/"), "-", name);
    let withVersion = safe ++ Lockfile.viewRealVersion(version);
    let tarball = cache /+ withVersion ++ ".tarball";
    if (! Files.isFile(tarball)) {
      Wget.download(~output=Path.v(tarball), url)
      |> RunAsync.runExn(~err="error downloading archive");
    };
    ExecCommand.execStringSync(
      ~cmd="tar xf " ++ tarball ++ " --strip-components 1 -C " ++ dest,
      (),
    )
    |> snd
    |> Files.expectSuccess("failed to untar");
  | Solution.Source.NoSource => ()
  | Solution.Source.GithubSource(user, repo, ref) =>
    let safe =
      Str.global_replace(
        Str.regexp("/"),
        "-",
        name ++ "__" ++ user ++ "__" ++ repo ++ "__" ++ ref,
      );
    let tarball = cache /+ safe ++ ".tarball";
    if (! Files.isFile(tarball)) {
      let tarUrl =
        "https://api.github.com/repos/"
        ++ user
        ++ "/"
        ++ repo
        ++ "/tarball/"
        ++ ref;
      Wget.download(~output=Path.v(tarball), tarUrl)
      |> RunAsync.runExn(~err="error downloading archive");
    };
    ExecCommand.execStringSync(
      ~cmd="tar xf " ++ tarball ++ " --strip-components 1 -C " ++ dest,
      (),
    )
    |> snd
    |> Files.expectSuccess("failed to untar");
  | Solution.Source.GitSource(gitUrl, commit) =>
    let safe = Str.global_replace(Str.regexp("/"), "-", name);
    let withVersion = safe ++ Lockfile.viewRealVersion(version);
    let tarball = cache /+ withVersion ++ ".tarball";
    if (! Files.isFile(tarball)) {
      print_endline(
        "[fetching git repo " ++ gitUrl ++ " at commit " ++ commit,
      );
      let gitdest = cache /+ "git-" ++ withVersion;
      /** TODO we want to have the commit nailed down by this point tho */
      ExecCommand.execStringSync(
        ~cmd="git clone " ++ gitUrl ++ " " ++ gitdest,
        (),
      )
      |> snd
      |> Files.expectSuccess("Unable to clone git repo " ++ gitUrl);
      ExecCommand.execStringSync(
        ~cmd=
          "cd "
          ++ gitdest
          ++ " && git checkout "
          ++ commit
          ++ " && rm -rf .git",
        (),
      )
      |> snd
      |> Files.expectSuccess(
           "Unable to checkout " ++ gitUrl ++ " at " ++ commit,
         );
      ExecCommand.execStringSync(
        ~cmd="tar czf " ++ tarball ++ " " ++ gitdest,
        (),
      )
      |> snd
      |> Files.expectSuccess("Unable to tar up");
      ExecCommand.execStringSync(~cmd="mv " ++ gitdest ++ " " ++ dest, ())
      |> snd
      |> Files.expectSuccess("Unable to move");
    } else {
      ExecCommand.execStringSync(
        ~cmd="tar xf " ++ tarball ++ " --strip-components 1 -C " ++ dest,
        (),
      )
      |> snd
      |> Files.expectSuccess("failed to untar");
    };
  | File(_) => failwith("Cannot handle a file source yet")
  };

/**
 * Unpack an archive into place, and then for opam projects create a package.json & apply files / patches.
 */
let unpackArchive = (dest, cache, name, version, source) =>
  if (Files.isDirectory(dest)) {
    print_endline("Dependency exists -- assuming it is fine " ++ dest);
  } else {
    Files.mkdirp(dest);
    let packageJson = dest /+ "package.json";
    let (source, maybeOpamFile) = source;
    getSource(dest, cache, name, version, source);
    switch (maybeOpamFile) {
    | Some((packageJson, files, patches)) =>
      if (Files.exists(dest /+ "esy.json")) {
        Unix.unlink(dest /+ "esy.json");
      };
      let raw =
        Yojson.Basic.pretty_to_string(Yojson.Safe.to_basic(packageJson));
      Files.writeFile(dest /+ "package.json", raw)
      |> Files.expectSuccess("could not write package.json");
      files
      |> List.iter(((relpath, contents)) => {
           Files.mkdirp(Filename.dirname(dest /+ relpath));
           Files.writeFile(dest /+ relpath, contents)
           |> Files.expectSuccess("could not write file " ++ relpath);
         });
      patches
      |> List.iter(abspath =>
           ExecCommand.execStringSync(
             ~cmd=
               Printf.sprintf(
                 "sh -c 'cd %s && patch -p1 < %s'",
                 dest,
                 abspath,
               ),
             (),
           )
           |> snd
           |> Files.expectSuccess("Failed to patch")
         );
    | None =>
      if (! Files.exists(packageJson)) {
        failwith("No opam file or package.json");
      };
      addResolvedFieldToPackageJson(packageJson, name, version);
    };
  };
