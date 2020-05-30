let cmd = {
  open Result.Syntax /* TODO: this is too specific for a library function. */;
  let req = "../esy-build-package/bin/esyRewritePrefixCommand.exe";
  let%bind cmd = NodeResolution.resolve(req);
  return(Cmd.ofPath(cmd));
};

let rewritePrefix = (~origPrefix, ~destPrefix, path) => {
  let%lwt () =
    Logs_lwt.debug(m =>
      m(
        "rewritePrefix %a: %a -> %a",
        Path.pp,
        path,
        Path.pp,
        origPrefix,
        Path.pp,
        destPrefix,
      )
    );
  let env = EsyBash.currentEnvWithMingwInPath;
  switch (cmd) {
  | Ok(cmd) =>
    ChildProcess.run(
      ~env=ChildProcess.CustomEnv(env),
      Cmd.(
        cmd
        % "--orig-prefix"
        % p(origPrefix)
        % "--dest-prefix"
        % p(destPrefix)
        % p(path)
      ),
    )
  | Error(`Msg(msg)) => Exn.failf("error: invalid esy installation: %s", msg)
  };
};

let replaceAllButFirstForwardSlashWithBack = s =>
  switch (String.split_on_char('/', s)) {
  | [hd, ...tl] => hd ++ "/" ++ String.concat("\\", tl)
  | [] => s
  };

let genSearchPrefixesForWin = (origPrefix, destPrefix) => {
  let origPrefixString = Path.show(origPrefix);
  let destPrefixString = Path.show(destPrefix);
  let normalizedOrigPrefix =
    Path.normalizePathSepOfFilename(origPrefixString);
  let normalizedDestPrefix =
    Path.normalizePathSepOfFilename(destPrefixString);
  let forwardSlashRegex = Str.regexp("/");
  let escapedOrigPrefix =
    Str.global_replace(forwardSlashRegex, "\\\\\\\\", normalizedOrigPrefix);

  let escapedDestPrefix =
    Str.global_replace(forwardSlashRegex, "\\\\\\\\", normalizedDestPrefix);

  let allButFirstFwd =
    replaceAllButFirstForwardSlashWithBack(
      Path.normalizePathSepOfFilename(origPrefixString),
    );
  [
    (origPrefixString, destPrefixString),
    (normalizedOrigPrefix, normalizedDestPrefix),
    (escapedOrigPrefix, escapedDestPrefix),
    (allButFirstFwd, normalizedDestPrefix),
  ];
};
