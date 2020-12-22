let esyStoreVersion = "3";

module Path = {
  include Path;
  let join = (x, y) => Filename.concat(x, y) |> Path.v;
};

let storeBuildTree = "b";
let storeInstallTree = "i";
let storeStageTree = "s";
let cwd = Sys.getcwd();
let releasePackagePath = cwd;
let releaseExportPath = Path.(v(releasePackagePath) / "_export");
let releaseBinPath = Path.(v(releasePackagePath) / "bin");
let unpaddedStorePath = Path.(v(releasePackagePath) / esyStoreVersion);

let getStorePathForPrefix = (prefix, ocamlPkgName, ocamlVersion) => {
  let ocamlrunStorePath =
    ocamlPkgName ++ "-" ++ ocamlVersion ++ "-########/bin/ocamlrun";

  let esyStorePaddingLength =
    127
    - String.length("!#")
    - String.length("/" ++ "i" ++ "/" ++ ocamlrunStorePath);
  let prefixLength = String.length(prefix ++ "/" ++ esyStoreVersion);
  let paddingLength = esyStorePaddingLength - prefixLength;
  if (paddingLength < 0) {
    failwith(
      "Esy prefix path is too deep in the filesystem, Esy won't be able to relocate artefacts",
    );
  };
  let p = Path.join(prefix, esyStoreVersion);
  Path.v(
    Path.show(p)
    ++ String.make(esyStorePaddingLength - String.length(Path.show(p)), '_'),
  );
};

type fileStat = {
  relative: Fpath.t,
  basename: Fpath.t,
  absolute: Fpath.t,
};

let fsWalk = (~dir) => {
  open RunAsync.Syntax;
  let rec inner = (~dirsInPath, ~relativePath, ~acc) => {
    switch (dirsInPath) {
    | [] => Lwt_result.return(acc)
    | [currentDirPath, ...restDir] =>
      let basename = Path.v(Path.basename(currentDirPath));
      let currentRelativePath =
        relativePath
        |> Option.map(~f=relativePath =>
             Fpath.append(relativePath, basename)
           )
        |> Option.orDefault(~default=basename);

      let%bind isDir = Fs.isDir(currentDirPath);

      let file = {
        relative: currentRelativePath,
        basename,
        absolute: currentDirPath,
      };
      if (isDir) {
        let%bind dirsInCurrentDirPath =
          Let_syntax.map(
            ~f=List.map(~f=name => Path.(currentDirPath / name)),
            Fs.listDir(currentDirPath),
          );
        inner(
          ~dirsInPath=List.rev_append(dirsInCurrentDirPath, restDir),
          ~relativePath,
          ~acc=[file, ...acc],
        );
      } else {
        inner(~dirsInPath=restDir, ~relativePath, ~acc=[file, ...acc]);
      };
    };
  };

  let%bind dirsInPath =
    Let_syntax.map(
      ~f=List.map(~f=name => Path.(dir / name)),
      Fs.listDir(dir),
    );
  inner(~dirsInPath, ~relativePath=None, ~acc=[]);
};

let importBuild = (filePath, maybeStorePath) => {
  open RunAsync.Syntax;
  let buildId =
    Str.global_replace(
      Str.regexp(".tar.gz$"),
      "",
      Fpath.basename(filePath),
    );

  print_endline("importing: " ++ buildId);

  switch (maybeStorePath) {
  | Some(storePath) =>
    let storeStagePath = Path.(storePath / storeStageTree); // 3_____/s
    let buildStagePath = Path.(storeStagePath / buildId); // 3_____/s/buildId
    let buildFinalPath = Path.(storePath / storeInstallTree / buildId); // 3_____/i/builId

    let%bind _ = Fs.createDir(buildStagePath);

    let%bind _ = Tarball.unpack(filePath, ~dst=storeStagePath);

    let%bind prevStorePrefix =
      Fs.readFile(Path.(buildStagePath / "_esy" / "storePrefix"));

    let%bind () =
      RewritePrefix.rewritePrefix(
        ~origPrefix=Path.v(prevStorePrefix),
        ~destPrefix=storePath,
        buildStagePath,
      );

    Fs.rename(~src=buildStagePath, buildFinalPath);

  | None =>
    let storeStagePath = Path.(unpaddedStorePath / storeStageTree);
    let buildStagePath = Path.(storeStagePath / buildId);
    let buildFinalPath = Path.(unpaddedStorePath / storeInstallTree / buildId);

    let%bind _ = Fs.createDir(buildStagePath);
    let%bind _ = Tarball.unpack(filePath, ~dst=storeStagePath);
    Fs.rename(~src=buildStagePath, buildFinalPath);
  };
};

let main = (ocamlPkgName, ocamlVersion, rewritePrefix) => {
  print_endline("[ocamlPkgName]: " ++ ocamlPkgName);
  print_endline("[ocamlVersion]: " ++ ocamlVersion);
  print_endline("[rewritePrefix]: " ++ string_of_bool(rewritePrefix));

  let check = () => {
    let%lwt buildFound = Fs.exists(releaseExportPath);
    switch (buildFound) {
    | Ok(true) =>
      if (!rewritePrefix) {
        Lwt.return(Ok());
      } else {
        let storePath =
          getStorePathForPrefix(
            releasePackagePath,
            ocamlPkgName,
            ocamlVersion,
          );
        let%lwt storeFound = Fs.exists(storePath);
        Lwt.return(
          switch (storeFound) {
          | Ok(true) => Error(`ReleaseAlreadyInstalled)
          | Ok(false) => Ok()
          | Error(err) => Error(`EsyLibError(err))
          },
        );
      }
    | Ok(false) => Lwt.return(Error(`NoBuildFound))
    | Error(err) => Lwt.return(Error(`EsyLibError(err)))
    };
  };

  let initStore = () => {
    open Lwt_result;
    let storePath =
      if (rewritePrefix) {
        getStorePathForPrefix(releasePackagePath, ocamlPkgName, ocamlVersion);
      } else {
        unpaddedStorePath;
      };

    Fs.createDir(storePath)
    >>= (
      _ =>
        RunAsync.List.waitAll([
          Fs.createDir(Path.(storePath / storeBuildTree)),
          Fs.createDir(Path.(storePath / storeInstallTree)),
          Fs.createDir(Path.(storePath / storeStageTree)),
        ])
    )
    |> Lwt_result.map_err(err => `EsyLibError(err));
  };

  let doImport = () => {
    open RunAsync.Syntax;
    let importBuilds = () => {
      open RunAsync.Syntax;
      let%bind files = fsWalk(~dir=releaseExportPath);
      let storePath =
        rewritePrefix
          ? Some(
              getStorePathForPrefix(
                releasePackagePath,
                ocamlPkgName,
                ocamlVersion,
              ),
            )
          : None;

      RunAsync.List.mapAndJoin(
        ~f=file => importBuild(file.absolute, storePath),
        files,
      );
    };

    let rewriteBinWrappers = () =>
      if (!rewritePrefix) {
        Lwt_result.return();
      } else {
        let storePath =
          getStorePathForPrefix(
            releasePackagePath,
            ocamlPkgName,
            ocamlVersion,
          );
        let%bind prevStorePath =
          Fs.readFile(Path.(releaseBinPath / "_storePath"));

        RewritePrefix.rewritePrefix(
          ~origPrefix=Path.v(prevStorePath),
          ~destPrefix=storePath,
          releaseBinPath,
        );
      };

    let%bind _ = importBuilds();
    rewriteBinWrappers();
  };

  Lwt_result.(
    check()
    >>= (
      _ =>
        initStore()
        >>= (_ => doImport() |> Lwt_result.map_err(err => `EsyLibError(err)))
    )
  );
};

open Cmdliner;

let ocamlPkgName = {
  let doc = "OCaml package name";
  Arg.(
    value
    & opt(string, "ocaml")
    & info(["ocaml-pkg-name"], ~docv="RELEASE CONFIG", ~doc)
  );
};

let ocamlVersion = {
  let doc = "OCaml package version";
  Arg.(
    value
    & opt(string, "n.00.0000")
    & info(["ocaml-version"], ~docv="RELEASE CONFIG", ~doc)
  );
};

let rewritePrefix = {
  let doc = "Whether to rewrite prefixes in the binary or not";
  Arg.(
    value
    & opt(bool, true)
    & info(["rewrite-prefix"], ~docv="RELEASE CONFIG", ~doc)
  );
};

let lwt_main = (ocamlPkgName, ocamlVersion, rewritePrefix) => {
  switch (Lwt_main.run(main(ocamlPkgName, ocamlVersion, rewritePrefix))) {
  | Ok(_) => print_endline("all ok")
  | Error(`NoBuildFound) => print_endline("No build found!")
  | Error(`ReleaseAlreadyInstalled) =>
    print_endline("Release already installed!")
  | Error(`EsyLibError(err)) => print_endline(EsyLib.Run.formatError(err))
  };
};

let main_t =
  Term.(const(lwt_main) $ ocamlPkgName $ ocamlVersion $ rewritePrefix);

let info = {
  let doc = "Export native builds and rewrite prefixes in them";
  let man = [`S(Manpage.s_bugs), `P("")];

  Term.info(
    "NatEsyInstallRelease",
    ~version="0.0.0",
    ~doc,
    ~exits=Term.default_exits,
    ~man,
  );
};

let () = Term.exit @@ Term.eval((main_t, info));
