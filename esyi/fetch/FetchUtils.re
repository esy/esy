open Shared;

module Cmd = EsyLib.Cmd;
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
  | Solution.Source.NoSource => ()
  | Solution.Source.File(_) => failwith("Cannot handle a file source yet")

  | Solution.Source.Archive(url, _checksum) =>
    let safe = Str.global_replace(Str.regexp("/"), "-", name);
    let withVersion = safe ++ Lockfile.viewRealVersion(version);
    let tarball = Path.(cache / (withVersion ++ ".tarball"));
    if (! Files.isFile(Path.toString(tarball))) {
      Wget.download(~output=tarball, url)
      |> RunAsync.runExn(~err="error downloading archive");
    };
    Tarball.unpack(~stripComponents=1, ~dst=dest, ~filename=tarball)
    |> RunAsync.runExn(~err="error unpacking");

  | Solution.Source.GithubSource(user, repo, ref) =>
    let safe =
      Str.global_replace(
        Str.regexp("/"),
        "-",
        name ++ "__" ++ user ++ "__" ++ repo ++ "__" ++ ref,
      );
    let tarball = Path.(cache / (safe ++ ".tarball"));
    if (! Files.isFile(Path.toString(tarball))) {
      let tarUrl =
        "https://api.github.com/repos/"
        ++ user
        ++ "/"
        ++ repo
        ++ "/tarball/"
        ++ ref;
      Wget.download(~output=tarball, tarUrl)
      |> RunAsync.runExn(~err="error downloading archive");
    };

    Tarball.unpack(~stripComponents=1, ~dst=dest, ~filename=tarball)
    |> RunAsync.runExn(~err="error unpacking");

  | Solution.Source.GitSource(gitUrl, commit) =>
    let safe = Str.global_replace(Str.regexp("/"), "-", name);
    let withVersion = safe ++ Lockfile.viewRealVersion(version);
    let tarball = Path.(cache / (withVersion ++ ".tarball"));
    if (! Files.isFile(Path.toString(tarball))) {
      print_endline(
        "[fetching git repo " ++ gitUrl ++ " at commit " ++ commit,
      );
      let gitdest = Path.(cache / ("git-" ++ withVersion));

      /** TODO we want to have the commit nailed down by this point tho */
      Git.clone(~dst=gitdest, ~remote=gitUrl)
      |> RunAsync.runExn(~err="error cloning repo");

      Git.checkout(~ref=commit, ~repo=gitdest)
      |> RunAsync.runExn(~err="error checkouting ref");

      ChildProcess.run(Cmd.(v("rm") % "-rf" % p(Path.(gitdest / ".git"))))
      |> RunAsync.runExn(~err="error checkouting ref");

      Tarball.create(~src=gitdest, ~filename=tarball)
      |> RunAsync.runExn(~err="error creating archive");

      ChildProcess.run(Cmd.(v("mv") % p(gitdest) % p(dest)))
      |> RunAsync.runExn(~err="error moving directory");
    } else {
      Tarball.unpack(~dst=dest, ~stripComponents=1, ~filename=tarball)
      |> RunAsync.runExn(~err="error extracting archive");
    };
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
    getSource(dest, cache, name, version, source);
    switch (maybeOpamFile) {
    | Some((packageJson, files, patches)) =>
      let%bind () = removeEsyJsonIfExists();

      let%bind () =
        Fs.writeJsonFile(~json=packageJson, Path.(dest / "package.json"));

      let%bind () =
        List.map(
          ((name, data)) => {
            let name = Path.append(dest, Path.v(name));
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
