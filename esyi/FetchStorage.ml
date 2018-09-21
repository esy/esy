module String = Astring.String

let sourceTarballPath ~cfg source =
  let id = Path.safePath (Source.show source) in
  Path.(cfg.Config.cacheTarballsPath // v id |> addExt "tgz")

let fetchSourceIntoPath' source path =
  let open RunAsync.Syntax in
  match source with

  | Source.LocalPath { path = srcPath; manifest = _; } ->
    let%bind names = Fs.listDir srcPath in
    let copy name =
      let src = Path.(srcPath / name) in
      let dst = Path.(path / name) in
      Fs.copyPath ~src ~dst
    in
    let%bind () =
      RunAsync.List.waitAll (List.map ~f:copy names)
    in
    return (Ok ())

  | Source.LocalPathLink _ ->
    (* this case is handled separately *)
    return (Ok ())

  | Source.NoSource ->
    return (Ok ())

  | Source.Archive {url; checksum}  ->
    let f tempPath =
      let%bind () = Fs.createDir tempPath in
      let tarballPath = Path.(tempPath / Filename.basename url) in
      match%lwt Curl.download ~output:tarballPath url with
      | Ok () ->
        let%bind () = Checksum.checkFile ~path:tarballPath checksum in
        let%bind () = Tarball.unpack ~stripComponents:1 ~dst:path tarballPath in
        return (Ok ())
      | Error err -> return (Error err)
    in
    Fs.withTempDir f

  | Source.Github github ->
    let f tempPath =
      let%bind () = Fs.createDir tempPath in
      let tarballPath = Path.(tempPath / "package.tgz") in
      let%bind () =
        let url =
          Printf.sprintf
            "https://api.github.com/repos/%s/%s/tarball/%s"
            github.user github.repo github.commit
        in
        Curl.download ~output:tarballPath url
      in
      let%bind () =  Tarball.unpack ~stripComponents:1 ~dst:path tarballPath in
      return (Ok ())
    in
    Fs.withTempDir f

  | Source.Git git ->
    let%bind () = Git.clone ~dst:path ~remote:git.remote () in
    let%bind () = Git.checkout ~ref:git.commit ~repo:path () in
    let%bind () = Fs.rmPath Path.(path / ".git") in
    return (Ok ())

let fetchSourceIntoCache ~cfg source =
  let open RunAsync.Syntax in
  let tarballPath = sourceTarballPath ~cfg source in

  let%bind tarballIsInCache = Fs.exists tarballPath in

  match tarballIsInCache with
  | true ->
    return (Ok tarballPath)
  | false ->
    Fs.withTempDir (fun sourcePath ->
      let%bind fetched =
        RunAsync.contextf (
          let%bind () = Fs.createDir sourcePath in
          fetchSourceIntoPath' source sourcePath
        )
        "fetching %a" Source.pp source
      in

      match fetched with
      | Ok () ->
        let%bind () =
          let%bind () = Fs.createDir (Path.parent tarballPath) in
          let tempTarballPath = Path.(tarballPath |> addExt ".tmp") in
          let%bind () = Tarball.create ~filename:tempTarballPath sourcePath in
          let%bind () = Fs.rename ~src:tempTarballPath tarballPath in
          return ()
        in
        return (Ok tarballPath)
      | Error err -> return (Error err)
    )

let fetchSource ~cfg source =
  let open RunAsync.Syntax in
  match%bind fetchSourceIntoCache ~cfg source with
  | Ok tarballPath -> return tarballPath
  | Error err -> Lwt.return (Error err)

module Dist = struct
  type t = {
    source : Source.t;
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
      begin match%bind fetchSourceIntoCache ~cfg source with
      | Ok (_ : Path.t) -> return {Dist. record; source;}
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
  let {Dist. source; record;} = dist in

  let finishInstall path =

    let%bind () =
      let f {Package.File. name; content; perm} =
        let name = Path.append path name in
        let dirname = Path.parent name in
        let%bind () = Fs.createDir dirname in
        (* TODO: move this to the place we read data from *)
        let contents =
          if String.get content (String.length content - 1) == '\n'
          then content
          else content ^ "\n"
        in
        let%bind () = Fs.writeFile ~perm ~data:contents name in
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
      EsyLinkFile.{source; override = record.override; opam = record.opam}
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
      let tarballPath = sourceTarballPath ~cfg dist.source in
      let%bind () = Tarball.unpack ~dst:path tarballPath in
      let%bind () = finishInstall path in
      return ()
  in

  return ()
