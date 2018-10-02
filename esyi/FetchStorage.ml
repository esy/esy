module String = Astring.String

module Dist = struct
  type t = {
    source : Source.t;
    sourceInStorage : SourceStorage.source;
    record : Solution.Record.t;
  }

  let pp fmt dist =
    Fmt.pf fmt "%s@%a" dist.record.name Version.pp dist.record.version
end

let fetch ~(cfg : Config.t) (record : Solution.Record.t) =
  let open RunAsync.Syntax in

  let rec fetch' errs sources =
    match sources with
    | source::rest ->
      begin match%bind SourceStorage.fetch ~cfg source with
      | Ok sourceInStorage -> return {Dist. record; source; sourceInStorage;}
      | Error err -> fetch' ((source, err)::errs) rest
      end
    | [] ->
      Logs_lwt.err (fun m ->
        let ppErr fmt (source, err) =
          Fmt.pf fmt
            "source: %a@\nerror: %a"
            Source.pp source
            Run.ppError err
        in
        m "unable to fetch %a:@[<v 2>@\n%a@]"
          Solution.Record.pp record
          Fmt.(list ~sep:(unit "@\n") ppErr) errs
      );%lwt
      error "installation error"
  in

  let sources =
    let main, mirrors = record.source in
    main::mirrors
  in

  fetch' [] sources

let install ~cfg ~path dist =
  let open RunAsync.Syntax in
  let {Dist. source; record; sourceInStorage;} = dist in

  let finishInstall path =

    let%bind () =
      let f file =
        let%bind _ = Package.File.writeToDir path file in
        return()
      in
      List.map ~f record.files |> RunAsync.List.waitAll
    in

    return ()
  in

  let%bind () = Fs.createDir path in

  (*
   * @andreypopp: We place _esylink before unpacking tarball, but that's just
   * because we get failures on Windows due to permission errors (reproducible
   * on AppVeyor).
   *
   * I'd prefer to place _esylink after unpacking tarball to prevent tarball
   * contents overriding _esylink accidentially but probability of such event
   * is low enough so I proceeded with the current order.
   *)
  let%bind () =
    EsyLinkFile.toDir
      EsyLinkFile.{source; overrides = record.overrides; opam = record.opam}
      path
  in

  let%bind () =
    match source with
    | Source.LocalPathLink _ ->
      return ()
    | Source.NoSource ->
      let%bind () = finishInstall path in
      return ()
    | _ ->
      let%bind () = SourceStorage.unpack ~cfg ~dst:path sourceInStorage in
      let%bind () = finishInstall path in
      return ()
  in

  return ()
