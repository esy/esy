open EsyLib
module Run = EsyBuildPackage.Run

let rewritePrefixInFile' ~origPrefix ~destPrefix path =
  Fastreplacestring.replace path origPrefix destPrefix

let rewritePrefixesInFile ~origPrefix ~destPrefix path =
  let open Result.Syntax in

  let origPrefixString = Path.show origPrefix in
  let destPrefixString = Path.show destPrefix in

  match System.Platform.host with

  | Windows ->
    rewritePrefixInFile'
      ~origPrefix:origPrefixString
      ~destPrefix:destPrefixString
      path;

    let normalizedOrigPrefix = Path.normalizePathSlashes origPrefixString in
    let normalizedDestPrefix = Path.normalizePathSlashes destPrefixString in
    let () =
      rewritePrefixInFile'
        ~origPrefix:normalizedOrigPrefix
        ~destPrefix:normalizedDestPrefix
        path
    in

    let () =
      let forwardSlashRegex = Str.regexp "/" in
      let escapedOrigPrefix =
        Str.global_replace forwardSlashRegex "\\\\\\\\" normalizedOrigPrefix
      in
      let escapedDestPrefix =
        Str.global_replace forwardSlashRegex "\\\\\\\\" normalizedDestPrefix
      in
      rewritePrefixInFile'
        ~origPrefix:escapedOrigPrefix
        ~destPrefix:escapedDestPrefix
        path
    in
    return ()

  | _ ->
    rewritePrefixInFile'
      ~origPrefix:origPrefixString
      ~destPrefix:destPrefixString
      path;
    return ()

let rewriteTargetInSymlink ~origPrefix ~destPrefix path =
  let open Result.Syntax in
  let%bind targetPath = Run.readlink path in
  match Path.remPrefix origPrefix targetPath with
  | Some basePath ->
    let nextTargetPath = Path.append destPrefix basePath in
    let%bind () = Run.rm path in
    let%bind () = Run.symlink ~target:nextTargetPath path in
    return ()
  | None -> return ()

let rewritePrefix ~origPrefix ~destPrefix rootPath =
  let relocate path stats =
    match stats.Unix.st_kind with
    | Unix.S_REG ->
      rewritePrefixesInFile
        ~origPrefix
        ~destPrefix
        path
    | Unix.S_LNK ->
      rewriteTargetInSymlink
        ~origPrefix
        ~destPrefix
        path
    | _ -> Ok ()
  in
  Run.traverse rootPath relocate

module CLI = struct
  open Cmdliner

  let exits = Term.default_exits
  let docs = Manpage.s_common_options
  let sdocs = Manpage.s_common_options
  let version = "%{VERSION}%"

  let origPrefix =
    let doc = "Prefix to rewrite." in
    Arg.(
      required
      & opt (some EsyLib.Cli.pathConv) None
      & info ["orig-prefix"] ~docs ~doc
    )

  let destPrefix =
    let doc = "New value of prefix." in
    Arg.(
      required
      & opt (some EsyLib.Cli.pathConv) None
      & info ["dest-prefix";] ~docs ~doc
    )

  let path =
    let doc = "Path to to rewrite prefix in." in
    Arg.(
      required
      & pos 0  (some EsyLib.Cli.pathConv) None
      & info [] ~doc ~docv:"PATH"
    )

  let defaultCommand =
    let doc = "Rewrite prefix in a directory" in
    let info = Term.info "esy-rewrite-prefix" ~version ~doc ~sdocs ~exits in
    let cmd origPrefix destPrefix path =
      match rewritePrefix ~origPrefix ~destPrefix path with
      | Ok () ->
        `Ok ()
      | Error (`Msg err) ->
        `Error (false, err)
      | Error (`CommandError (cmd, _)) ->
        `Error (false, "error running command: " ^ Bos.Cmd.to_string cmd)
    in
    Term.(ret (const cmd $ origPrefix $ destPrefix $ path)), info

  let run () =
    Printexc.record_backtrace true;
    Term.(exit (eval ~argv:Sys.argv defaultCommand))
end

let () = CLI.run()
