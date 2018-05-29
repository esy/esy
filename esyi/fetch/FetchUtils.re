open Shared;

module Fs = EsyLib.Fs;
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

let addResolvedFieldToPackageJson = (filename: Path.t, name, version) =>
  RunAsync.Syntax.(
    switch%bind (Fs.readJsonFile(filename)) {
    | `Assoc(items) =>
      let json =
        `Assoc([
          ("_resolved", `String(resolvedString(name, version))),
          ...items,
        ]);
      let data = Yojson.Safe.pretty_to_string(json);
      Fs.writeFile(~data, filename);
    | _ => error("invalid package.json")
    }
  );

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
let unpackArchive = (dest: Path.t, cache, name, version, source) => {
  open RunAsync.Syntax;
  let removeEsyJsonIfExists = () => {
    let esyJson = Path.(dest / "esy.json");
    switch%bind (Fs.exists(esyJson)) {
    | true => Fs.unlink(esyJson)
    | false => return()
    };
  };
  if%bind (Fs.exists(dest)) {
    print_endline(
      "Dependency exists -- assuming it is fine " ++ Path.toString(dest),
    );
    return();
  } else {
    let%bind () = Fs.createDirectory(dest);
    let (source, maybeOpamFile) = source;
    getSource(Path.toString(dest), cache, name, version, source);
    switch (maybeOpamFile) {
    | Some((packageJson, files, patches)) =>
      let%bind () = removeEsyJsonIfExists();

      let%bind () =
        Fs.writeJsonFile(~json=packageJson, Path.(dest / "package.json"));

      let%bind () =
        List.map(
          ((name, data)) => {
            let name = Path.(dest / name);
            let dirname = Path.parent(name);
            let%bind () = Fs.createDirectory(dirname);
            let%bind () = Fs.writeFile(~data, name);
            return();
          },
          files,
        )
        |> RunAsync.List.waitAll;

      patches
      |> List.iter(abspath =>
           ExecCommand.execStringSync(
             ~cmd=
               Printf.sprintf(
                 "sh -c 'cd %s && patch -p1 < %s'",
                 Path.toString(dest),
                 abspath,
               ),
             (),
           )
           |> snd
           |> Files.expectSuccess("Failed to patch")
         );
      return();

    | None =>
      let packageJson = Path.(dest / "package.json");
      if%bind (Fs.exists(packageJson)) {
        addResolvedFieldToPackageJson(packageJson, name, version);
      } else {
        error("No opam file or package.json");
      };
    };
  };
};
