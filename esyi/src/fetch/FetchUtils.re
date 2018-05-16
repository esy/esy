
open Shared;

let (/+) = Filename.concat;

let resolvedString = (name, version) => Types.resolvedPrefix ++ name ++ "--" ++ Lockfile.viewRealVersion(version);

/** Hack to always cache the ocaml build :P */
let resolveString = (name, version) => name == "ocaml"
  ? "esyi4-" ++ name ++ "--" ++ Lockfile.viewRealVersion(version)
  : resolvedString(name, version);

let addResolvedFieldToPackageJson = (filename, name, version) => {
  let json = switch (Yojson.Basic.from_file(filename)) {
  | `Assoc(items) => items
  | _ => failwith("bad json")
  };
  let raw = Yojson.Basic.pretty_to_string(`Assoc([("_resolved", `String(resolvedString(name, version))), ...json]));
  Files.writeFile(filename, raw) |> Files.expectSuccess("Could not write back package json");
};

let absname = (name, version) => {
  name ++ "__" ++ Lockfile.viewRealVersion(version)
};

/**
 * Unpack an archive into place, and then for opam projects create a package.json & apply files / patches.
 */
let unpackArchive = (dest, cache, name, version, source) => {
  if (Files.isDirectory(dest)) {
    print_endline("Dependency exists -- assuming it is fine " ++ dest)
  } else {
    Files.mkdirp(dest);

    let getSource = source => {switch source {
    | Types.Source.Archive(url, _checksum) => {
      let safe = Str.global_replace(Str.regexp("/"), "-", name);
      let withVersion = safe ++ Lockfile.viewRealVersion(version);
      let tarball = cache /+ withVersion ++ ".tarball";
      if (!Files.isFile(tarball)) {
        ExecCommand.execSync(~cmd="curl -L --output "++ tarball ++ " " ++ url, ()) |> snd |> Files.expectSuccess("failed to fetch with curl");
      };
      ExecCommand.execSync(~cmd="tar xf " ++ tarball ++ " --strip-components 1 -C " ++ dest, ()) |> snd |> Files.expectSuccess("failed to untar");
    }
    | Types.Source.NoSource => ()
    | Types.Source.GithubSource(user, repo, ref) => {
      let safe = Str.global_replace(Str.regexp("/"), "-", name ++ "__" ++ user ++ "__" ++ repo ++ "__" ++ ref);
      let tarball = cache /+ safe ++ ".tarball";
      if (!Files.isFile(tarball)) {
        let tarUrl = "https://api.github.com/repos/" ++ user ++ "/" ++ repo ++ "/tarball/" ++ ref;
        ExecCommand.execSync(~cmd="curl -L --output "++ tarball ++ " " ++ tarUrl, ()) |> snd |> Files.expectSuccess("failed to fetch with curl");
      };
      ExecCommand.execSync(~cmd="tar xf " ++ tarball ++ " --strip-components 1 -C " ++ dest, ()) |> snd |> Files.expectSuccess("failed to untar");
    }
    | Types.Source.GitSource(gitUrl, commit) => {
      let safe = Str.global_replace(Str.regexp("/"), "-", name);
      let withVersion = safe ++ Lockfile.viewRealVersion(version);
      let tarball = cache /+ withVersion ++ ".tarball";
      if (!Files.isFile(tarball)) {
        print_endline("[fetching git repo " ++ gitUrl ++ " at commit " ++ commit);
        let gitdest = cache /+ "git-" ++ withVersion;
        /** TODO we want to have the commit nailed down by this point tho */
        ExecCommand.execSync(~cmd="git clone " ++ gitUrl ++ " " ++ gitdest, ()) |> snd |> Files.expectSuccess("Unable to clone git repo " ++ gitUrl);
        ExecCommand.execSync(~cmd="cd " ++ gitdest ++ " && git checkout " ++ commit ++ " && rm -rf .git", ()) |> snd |> Files.expectSuccess("Unable to checkout " ++ gitUrl ++ " at " ++ commit);
        ExecCommand.execSync(~cmd="tar czf " ++ tarball ++ " " ++ gitdest, ()) |> snd |> Files.expectSuccess("Unable to tar up");
        ExecCommand.execSync(~cmd="mv " ++ gitdest ++ " " ++ dest, ()) |> snd |> Files.expectSuccess("Unable to move");
      } else {
        ExecCommand.execSync(~cmd="tar xf " ++ tarball ++ " --strip-components 1 -C " ++ dest, ()) |> snd |> Files.expectSuccess("failed to untar");
      }
    }
    | File(_) => failwith("Cannot handle a file source yet")
    }};

    let packageJson = dest /+ "package.json";
    let (source, maybeOpamFile) = source;
    getSource(source);
    switch maybeOpamFile {
    | Some((packageJson, files, patches)) => {
      if (Files.exists(dest /+ "esy.json")) {
        Unix.unlink(dest /+ "esy.json");
      };
      let raw = Yojson.Basic.pretty_to_string(Yojson.Safe.to_basic(packageJson));
      Files.writeFile(dest /+ "package.json", raw) |> Files.expectSuccess("could not write package.json");
      files |> List.iter(((relpath, contents)) => {
        Files.mkdirp(Filename.dirname(dest /+ relpath));
        Files.writeFile(dest /+ relpath, contents) |> Files.expectSuccess("could not write file " ++ relpath)
      });

      patches |> List.iter((abspath) => {
        ExecCommand.execSync(
          ~cmd=Printf.sprintf("sh -c 'cd %s && patch -p1 < %s'", dest, abspath),
          ()
        ) |> snd |> Files.expectSuccess("Failed to patch")
      });
    }
    | None => {
      if (!Files.exists(packageJson)) {
        failwith("No opam file or package.json");
      };
      addResolvedFieldToPackageJson(packageJson, name, version);
    }
    };
  }
};