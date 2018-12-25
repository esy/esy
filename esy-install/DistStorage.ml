open EsyPackageConfig

module CachePaths = struct
  let key dist =
    Digest.to_hex (Digest.string (Dist.show dist))

  let fetchedDist sandbox dist =
    Path.(SandboxSpec.distPath sandbox / key dist)

  let cachedDist cfg dist =
    Path.(cfg.Config.sourceFetchPath / key dist)
end

(* dist which is fetched *)
type fetchedDist =
  (* no sources, corresponds to Dist.NoSource *)
  | Empty
  (* cached source path which could be safely removed *)
  | Path of Path.t
  (* source path from some local package, should be retained *)
  | SourcePath of Path.t
  (* downloaded tarball *)
  | Tarball of {tarballPath : Path.t; stripComponents : int;}

let cache fetched tarballPath =
  let open RunAsync.Syntax in
  match fetched with
  | Empty ->
    let%bind unpackPath = Fs.randomPathVariation tarballPath in
    let%bind tempTarballPath = Fs.randomPathVariation tarballPath in
    let%bind () = Fs.createDir unpackPath in
    let%bind () = Tarball.create ~filename:tempTarballPath unpackPath in
    let%bind () = Fs.rename ~src:tempTarballPath tarballPath in
    let%bind () = Fs.rmPath unpackPath in
    return (Tarball {tarballPath; stripComponents = 0;})
  | SourcePath path ->
    let%bind tempTarballPath = Fs.randomPathVariation tarballPath in
    let%bind () = Tarball.create ~filename:tempTarballPath path in
    let%bind () = Fs.rename ~src:tempTarballPath tarballPath in
    return (Tarball {tarballPath; stripComponents = 0;})
  | Path path ->
    let%bind tempTarballPath = Fs.randomPathVariation tarballPath in
    let%bind () = Tarball.create ~filename:tempTarballPath path in
    let%bind () = Fs.rename ~src:tempTarballPath tarballPath in
    let%bind () = Fs.rmPath path in
    return (Tarball {tarballPath; stripComponents = 0;})
  | Tarball info ->
    let%bind tempTarballPath = Fs.randomPathVariation tarballPath in
    let%bind unpackPath = Fs.randomPathVariation info.tarballPath in
    let%bind () = Tarball.unpack ~stripComponents:1 ~dst:unpackPath info.tarballPath in
    let%bind () = Tarball.create ~filename:tempTarballPath unpackPath in
    let%bind () = Fs.rename ~src:tempTarballPath tarballPath in
    let%bind () = Fs.rmPath info.tarballPath in
    let%bind () = Fs.rmPath unpackPath in
    return (Tarball {tarballPath; stripComponents = 0;})

let ofCachedTarball path = Tarball {tarballPath = path; stripComponents = 0;}
let ofDir path = SourcePath path

let fetch' sandbox dist =
  let open RunAsync.Syntax in
  let tempPath = SandboxSpec.tempPath sandbox in
  match dist with

  | Dist.LocalPath { path = srcPath; manifest = _; } ->
    let srcPath = DistPath.toPath sandbox.SandboxSpec.path srcPath in
    return (SourcePath srcPath)

  | Dist.NoSource ->
    return Empty

  | Dist.Archive {url; checksum}  ->
    let path = CachePaths.fetchedDist sandbox dist in
    Fs.withTempDir ~tempPath (fun stagePath ->
      let%bind () = Fs.createDir stagePath in
      let tarballPath = Path.(stagePath / "archive") in
      let%bind () = Curl.download ~output:tarballPath url in
      let%bind () = Checksum.checkFile ~path:tarballPath checksum in
      let%bind () = Fs.createDir (Path.parent path) in
      let%bind () = Fs.rename ~src:tarballPath path in
      return (Tarball {tarballPath = path; stripComponents = 1;})
    )

  | Dist.Github github ->
    let path = CachePaths.fetchedDist sandbox dist in
    let%bind () = Fs.createDir (Path.parent path) in
    Fs.withTempDir ~tempPath (fun stagePath ->
      let%bind () = Fs.createDir stagePath in
      let tarballPath = Path.(stagePath / "archive.tgz") in
      let url =
        Printf.sprintf
          "https://api.github.com/repos/%s/%s/tarball/%s"
          github.user github.repo github.commit
      in
      let%bind () = Curl.download ~output:tarballPath url in
      let%bind () = Fs.rename ~src:tarballPath path in
      return (Tarball {tarballPath = path; stripComponents = 1;})
    )

  | Dist.Git git ->
    let path = CachePaths.fetchedDist sandbox dist in
    let%bind () = Fs.createDir (Path.parent path) in
    Fs.withTempDir ~tempPath (fun stagePath ->
      let%bind () = Fs.createDir stagePath in
      let%bind () = Git.clone ~dst:stagePath ~remote:git.remote () in
      let%bind () = Git.checkout ~ref:git.commit ~repo:stagePath () in
      let%bind () = Fs.rmPath Path.(stagePath / ".git") in
      let%bind () = Fs.rename ~src:stagePath path in
      return (Path path)
    )

let fetch ~cfg:_ ~sandbox dist =
  RunAsync.contextf
    (fetch' sandbox dist)
    "fetching dist: %a" Dist.pp dist

(* unpack fetched dist into directory *)
let unpack fetched path =
  let open RunAsync.Syntax in
  match fetched with
  | Empty -> Fs.createDir path
  | SourcePath srcPath
  | Path srcPath ->
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
  | Tarball {tarballPath; stripComponents;} ->
    Tarball.unpack ~stripComponents ~dst:path tarballPath

let fetchIntoCache ~cfg ~sandbox (dist : Dist.t) =
  let open RunAsync.Syntax in
  let path = CachePaths.cachedDist cfg dist in
  if%bind Fs.exists path
  then return path
  else
    let%bind fetched = fetch ~cfg ~sandbox dist in
    let%bind () = unpack fetched path in
    return path
