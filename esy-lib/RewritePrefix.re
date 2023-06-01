let cmd = {
  let dir = Path.(exePath() |> parent |> parent);
  Path.(dir / "lib" / "esy" / "esyRewritePrefixCommand") |> Cmd.ofPath;
};

let rewritePrefix = (~origPrefix, ~destPrefix, path) => {
  let%lwt () =
    Esy_logs_lwt.debug(m =>
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
  );
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
