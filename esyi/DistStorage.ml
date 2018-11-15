let distId dist =
  Digest.to_hex (Digest.string (Dist.show dist))

let distTarballPath ~cfg dist =
  match cfg.Config.sourceArchivePath with
  | Some sourceArchivePath ->
    let id = distId dist in
    Some Path.(sourceArchivePath // v id |> addExt "tgz")
  | None -> None

let distCachePath ~cfg dist =
  Path.(cfg.Config.sourceFetchPath / distId dist)

let fetchDistIntoPath' root source path =
  let open RunAsync.Syntax in
  match source with

  | Dist.LocalPath { path = srcPath; manifest = _; } ->
    let srcPath = DistPath.toPath root srcPath in
    let%bind names = Fs.listDir srcPath in
    let copy name =
      let src = Path.(srcPath / name) in
      let dst = Path.(path / name) in
      Fs.copyPath ~src ~dst
    in
    let%bind () =
      RunAsync.List.mapAndWait ~f:copy names
    in
    return ()

  | Dist.NoSource ->
    return ()

  | Dist.Archive {url; checksum}  ->
    let f tempPath =
      let%bind () = Fs.createDir tempPath in
      let tarballPath = Path.(tempPath / Filename.basename url) in
      let%bind () = Curl.download ~output:tarballPath url in
      let%bind () = Checksum.checkFile ~path:tarballPath checksum in
      let%bind () = Tarball.unpack ~stripComponents:1 ~dst:path tarballPath in
      return ()
    in
    Fs.withTempDir f

  | Dist.Github github ->
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
      return ()
    in
    Fs.withTempDir f

  | Dist.Git git ->
    let%bind () = Git.clone ~dst:path ~remote:git.remote () in
    let%bind () = Git.checkout ~ref:git.commit ~repo:path () in
    let%bind () = Fs.rmPath Path.(path / ".git") in
    return ()

let fetchDistIntoPath ~cfg ~sandbox dist path =
  let open RunAsync.Syntax in
  match distTarballPath ~cfg dist with
  | Some tarballPath ->
    begin match%bind Fs.exists tarballPath with
    | true ->
      Tarball.unpack ~dst:path tarballPath
    | false ->
      let%bind () =
        fetchDistIntoPath' sandbox.SandboxSpec.path dist path
      in
      let%bind () =
        let%bind () = Fs.createDir (Path.parent tarballPath) in
        let tempTarballPath = Path.(tarballPath |> addExt ".tmp") in
        let%bind () = Tarball.create ~filename:tempTarballPath path in
        let%bind () = Fs.rename ~src:tempTarballPath tarballPath in
        return ()
      in
      return ()
    end
  | None ->
    fetchDistIntoPath' sandbox.SandboxSpec.path dist path

let fetch ~cfg ~sandbox dist path =
  RunAsync.contextf
    (fetchDistIntoPath ~cfg ~sandbox dist path)
    "fetching dist: %a" Dist.pp dist

let fetchIntoCache ~cfg ~sandbox (dist : Dist.t) =
  let open RunAsync.Syntax in
  let path = distCachePath ~cfg dist in
  if%bind Fs.exists path
  then return path
  else
    let%bind () = fetch ~cfg ~sandbox dist path in
    return path
