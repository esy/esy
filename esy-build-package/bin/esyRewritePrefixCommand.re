open EsyLib;
module Run = EsyBuildPackage.Run;

let rewritePrefixInFile' = (~origPrefix, ~destPrefix, path) =>
  switch (Fastreplacestring.replace(Path.show(path), origPrefix, destPrefix)) {
  | Ok () => Ok()
  | Error(msg) => Error(`Msg(msg))
  };

let rewritePrefixesInFile = (~origPrefix, ~destPrefix, path) => {
  open Result.Syntax;

  let origPrefixString = Path.show(origPrefix);
  let destPrefixString = Path.show(destPrefix);

  switch (System.Platform.host) {
  | Windows =>
    let%bind () =
      rewritePrefixInFile'(
        ~origPrefix=origPrefixString,
        ~destPrefix=destPrefixString,
        path,
      );

    let normalizedOrigPrefix = Path.normalizePathSlashes(origPrefixString);
    let normalizedDestPrefix = Path.normalizePathSlashes(destPrefixString);
    let%bind () =
      rewritePrefixInFile'(
        ~origPrefix=normalizedOrigPrefix,
        ~destPrefix=normalizedDestPrefix,
        path,
      );

    let%bind () = {
      let forwardSlashRegex = Str.regexp("/");
      let escapedOrigPrefix =
        Str.global_replace(
          forwardSlashRegex,
          "\\\\\\\\",
          normalizedOrigPrefix,
        );

      let escapedDestPrefix =
        Str.global_replace(
          forwardSlashRegex,
          "\\\\\\\\",
          normalizedDestPrefix,
        );

      rewritePrefixInFile'(
        ~origPrefix=escapedOrigPrefix,
        ~destPrefix=escapedDestPrefix,
        path,
      );
    };

    return();

  | _ =>
    rewritePrefixInFile'(
      ~origPrefix=origPrefixString,
      ~destPrefix=destPrefixString,
      path,
    )
  };
};

let rewriteTargetInSymlink = (~origPrefix, ~destPrefix, path) => {
  open Result.Syntax;
  let%bind targetPath = Run.readlink(path);
  switch (Path.remPrefix(origPrefix, targetPath)) {
  | Some(basePath) =>
    let nextTargetPath = Path.append(destPrefix, basePath);
    let%bind () = Run.rm(path);
    let%bind () = Run.symlink(~target=nextTargetPath, path);
    return();
  | None => return()
  };
};

let rewritePrefix = (~origPrefix, ~destPrefix, rootPath) => {
  let relocate = (path, stats) =>
    switch (stats.Unix.st_kind) {
    | Unix.S_REG => rewritePrefixesInFile(~origPrefix, ~destPrefix, path)
    | Unix.S_LNK => rewriteTargetInSymlink(~origPrefix, ~destPrefix, path)
    | _ => Ok()
    };

  Run.traverse(rootPath, relocate);
};

module CLI = {
  open Cmdliner;

  let exits = Term.default_exits;
  let docs = Manpage.s_common_options;
  let sdocs = Manpage.s_common_options;
  let version = "%{VERSION}%";

  let origPrefix = {
    let doc = "Prefix to rewrite.";
    Arg.(
      required
      & opt(some(EsyLib.Cli.pathConv), None)
      & info(["orig-prefix"], ~docs, ~doc)
    );
  };

  let destPrefix = {
    let doc = "New value of prefix.";
    Arg.(
      required
      & opt(some(EsyLib.Cli.pathConv), None)
      & info(["dest-prefix"], ~docs, ~doc)
    );
  };

  let path = {
    let doc = "Path to to rewrite prefix in.";
    Arg.(
      required
      & pos(0, some(EsyLib.Cli.pathConv), None)
      & info([], ~doc, ~docv="PATH")
    );
  };

  let defaultCommand = {
    let doc = "Rewrite prefix in a directory";
    let info =
      Term.info("esy-rewrite-prefix", ~version, ~doc, ~sdocs, ~exits);
    let cmd = (origPrefix, destPrefix, path) =>
      switch (rewritePrefix(~origPrefix, ~destPrefix, path)) {
      | Ok () => `Ok()
      | Error(`Msg(err)) => `Error((false, err))
      | Error(`CommandError(cmd, _)) =>
        `Error((false, "error running command: " ++ Bos.Cmd.to_string(cmd)))
      };

    (Term.(ret(const(cmd) $ origPrefix $ destPrefix $ path)), info);
  };

  let run = () => {
    Printexc.record_backtrace(true);
    Term.(exit(eval(~argv=Sys.argv, defaultCommand)));
  };
};

let () = CLI.run();
