open Esy_cmdliner;
open RunAsync.Syntax;

let esyStoreVersion = Store.version;

let noBuildFoundMsg = "No build found!";
let releaseAlreadyInstalled = "Release already installed!";

module Path = {
  include Path;
  let join = (x, y) => Filename.concat(x, y) |> Path.v;
};

let storeBuildTree = Store.buildTree;
let storeInstallTree = Store.installTree;
let storeStageTree = Store.stageTree;
let cwd = Sys.getcwd();
let releasePackagePath = cwd;
let releaseExportPath = Path.(v(releasePackagePath) / "_export");
let releaseBinPath = Path.(v(releasePackagePath) / "bin");

type rewritePrefix =
  | Rewrite(Path.t)
  | NoRewrite(Path.t);

let getStorePathForPrefix = (prefix, ocamlPkgName, ocamlVersion) => {
  switch (Store.getPadding(~ocamlPkgName, ~ocamlVersion, Path.v(prefix))) {
  | Error(`Msg(err)) => Run.error(err)
  | Ok(padding) => Ok(Path.join(prefix, esyStoreVersion ++ padding))
  };
};

let importBuild = (~rewritePrefix, filePath) => {
  switch (rewritePrefix) {
  | Rewrite(storePath) =>
    EsyBuild.BuildSandbox.importBuild(storePath, filePath)
  | NoRewrite(storePath) =>
    let buildId =
      Str.global_replace(
        Str.regexp(".tar.gz$"),
        "",
        Fpath.basename(filePath),
      );
    let storeStagePath = Path.(storePath / storeStageTree);
    let buildStagePath = Path.(storeStagePath / buildId);
    let buildFinalPath = Path.(storePath / storeInstallTree / buildId);

    let* () = Fs.createDir(buildStagePath);
    let* () = Tarball.unpack(filePath, ~dst=storeStagePath);
    Fs.rename(~src=buildStagePath, buildFinalPath);
  };
};

let main = rewritePrefix => {
  let storePath =
    switch (rewritePrefix) {
    | Rewrite(path)
    | NoRewrite(path) => path
    };

  let check = () => {
    let* buildFound =
      releaseExportPath
      |> Fs.exists
      |> RunAsync.try_(~catch=_ => RunAsync.return(false));
    if (buildFound) {
      switch (rewritePrefix) {
      | NoRewrite(_) => Lwt.return(Ok())
      | Rewrite(storePath) =>
        let* storeFound =
          storePath
          |> Fs.exists
          |> RunAsync.try_(~catch=_ => RunAsync.return(false));
        if (storeFound) {
          RunAsync.error(releaseAlreadyInstalled);
        } else {
          RunAsync.return();
        };
      };
    } else {
      RunAsync.error(noBuildFoundMsg);
    };
  };
  let initStore = () => {
    let* () = Fs.createDir(storePath);
    RunAsync.List.waitAll([
      Fs.createDir(Path.(storePath / storeBuildTree)),
      Fs.createDir(Path.(storePath / storeInstallTree)),
      Fs.createDir(Path.(storePath / storeStageTree)),
    ]);
  };
  let doImport = () => {
    open RunAsync.Syntax;
    let importBuilds = () => {
      open RunAsync.Syntax;
      let* files = Fs.listDir(releaseExportPath);
      files
      |> List.map(~f=Path.addSeg(releaseExportPath))
      |> RunAsync.List.mapAndWait(~f=importBuild(~rewritePrefix));
    };
    let rewriteBinWrappers = () =>
      switch (rewritePrefix) {
      | NoRewrite(_) => Lwt_result.return()
      | Rewrite(storePath) =>
        let* prevStorePath =
          Fs.readFile(Path.(releaseBinPath / "_storePath"));
        RewritePrefix.rewritePrefix(
          ~origPrefix=Path.v(prevStorePath),
          ~destPrefix=storePath,
          releaseBinPath,
        );
      };
    let* () = importBuilds();
    rewriteBinWrappers();
  };
  let* () = check();
  let* () = initStore();
  let* () = doImport();

  switch (System.Platform.host, System.Arch.host) {
  | (Darwin, Arm64) =>
    open RunAsync.Syntax;
    print_endline("Detected macOS arm64. Signing binaries...");
    let entries =
      switch (
        Path.v(releasePackagePath)
        |> EsyBuildPackage.Build.getMachOBins(
             (module EsyBuildPackage.Run),
             [],
           )
      ) {
      | Ok(entries) => entries
      | _ => []
      };
    let binariesThatFailedToSign = EsyBuildPackage.BigSurArm.sign(entries);
    if (List.length(binariesThatFailedToSign) > 0) {
      Esy_logs.warn(m =>
        m("# esy-build-package: Failed to sign the following binaries")
      );
      let f = binary => {
        ignore @@ Esy_logs.warn(m => m("  %a", Path.pp, binary));
      };
      List.iter(~f, binariesThatFailedToSign);
      return();
    } else {
      return();
    };

  | _ => Lwt.return(Ok())
  };
};

let lwt_main = (ocamlPkgName, ocamlVersion, shouldRewritePrefix) => {
  let rewritePrefix = () => {
    let* storePath =
      RunAsync.ofRun @@
      getStorePathForPrefix(releasePackagePath, ocamlPkgName, ocamlVersion);
    RunAsync.return(Rewrite(storePath));
  };
  let unpaddedStorePath = Path.(v(releasePackagePath) / esyStoreVersion);

  {
    let* rewritePrefix =
      shouldRewritePrefix
        ? rewritePrefix() : RunAsync.return(NoRewrite(unpaddedStorePath));
    main(rewritePrefix);
  }
  |> EsyLib.Cli.runAsyncToEsy_cmdlinerRet;
};

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
