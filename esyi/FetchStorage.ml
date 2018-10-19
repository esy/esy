module String = Astring.String

module Dist = struct
  type t = {
    source : Source.t;
    sourceInStorage : SourceStorage.source option;
    pkg : Solution.Package.t;
  }

  let id dist = Solution.Package.id dist.pkg
  let source dist = dist.source
  let pp fmt dist =
    Fmt.pf fmt "%s@%a" dist.pkg.name Version.pp dist.pkg.version
end

let fetch ~sandbox (pkg : Solution.Package.t) =
  let open RunAsync.Syntax in

  let rec fetch' errs sources =
    match sources with
    | source::rest ->
      begin match%bind SourceStorage.fetch ~cfg:sandbox.Sandbox.cfg source with
      | Ok sourceInStorage -> return {Dist. pkg; source; sourceInStorage = Some sourceInStorage;}
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
          Solution.Package.pp pkg
          Fmt.(list ~sep:(unit "@\n") ppErr) errs
      );%lwt
      error "installation error"
  in

  match pkg.source with
  | Solution.Package.Link {path; manifest; overrides = _;} ->
    return {
      Dist. pkg;
      source = Source.LocalPathLink {path;manifest;};
      sourceInStorage = None;
    }
  | Solution.Package.Install {source = main, mirrors; _} ->
    fetch' [] (main::mirrors)

let unpack ~sandbox ~path ~overrides ~files ~opam dist =
  let open RunAsync.Syntax in

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
    match dist.Dist.sourceInStorage with
    | None ->
      return ()
    | Some sourceInStorage ->
      let tempPath = Path.(path |> addExt ".tmp") in
      let%bind () = Fs.rmPath tempPath in
      let%bind () = Fs.createDir tempPath in

      let%bind () =
        EsyLinkFile.toDir
          EsyLinkFile.{source = dist.Dist.source; overrides; opam;}
          tempPath
      in
      let%bind () = SourceStorage.unpack ~cfg:sandbox.Sandbox.cfg ~dst:tempPath sourceInStorage in
      let%bind () =
        let f file =
          Package.File.writeToDir ~destinationDir:tempPath file
        in
        List.map ~f files |> RunAsync.List.waitAll
      in

      let%bind () = Fs.rename ~src:tempPath path in
      return ()
  in

  return ()

let path ~cfg dist =
  let name = Path.safeSeg dist.Dist.pkg.name in
  let id =
    Source.show dist.Dist.source
    |> Digest.string
    |> Digest.to_hex
    |> Path.safeSeg
  in
  Path.(cfg.Config.cacheSourcesPath / (name ^ "-" ^ id))

type status =
  | Cached
  | Fresh

let install ~sandbox dist =
  (** TODO: need to sync here so no two same tasks are running at the same time *)
  let open RunAsync.Syntax in
  RunAsync.contextf (
    match dist.Dist.pkg.source with
    | Solution.Package.Link {path; _} ->
      return (Fresh, Path.(sandbox.Sandbox.spec.path // path))
    | Solution.Package.Install { overrides; files; opam; _ } ->
      let path = path ~cfg:sandbox.Sandbox.cfg dist in
      if%bind Fs.exists path
      then return (Cached, path)
      else (
        let%bind () = unpack ~sandbox ~overrides ~files ~path ~opam dist in
        return (Fresh, path)
      )
  ) "installing %a" Dist.pp dist
