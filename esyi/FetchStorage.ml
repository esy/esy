module String = Astring.String

module Dist = struct
  type t = {
    name : string;
    version : Version.t;
    source : Source.t;
    override : Package.Override.t option;
    tarballPath : Path.t option;
  }

  let pp fmt dist =
    Fmt.pf fmt "%s@%a" dist.name Version.pp dist.version
end

let cacheId source (record : Solution.Record.t) =

  let hash vs =
    vs
    |> String.concat ~sep:"__"
    |> Digest.string
    |> Digest.to_hex
    |> String.Sub.v ~start:0 ~stop:8
    |> String.Sub.to_string
  in
  let version = Version.toString record.version in
  let source = Source.toString source in
  match record.opam with
  | None ->
    Printf.sprintf "%s__%s__%s_v2" record.name version (hash [source])
  | Some opam ->
    let h = hash [
      source;
      opam.opam
      |> Package.Opam.OpamFile.to_yojson
      |> Yojson.Safe.to_string;
      (match opam.override with
      | Some override ->
        override
        |> Package.OpamOverride.to_yojson
        |> Yojson.Safe.to_string
      | None -> "");
    ] in
    Printf.sprintf "%s__%s__%s_v2" record.name version h

let fetch ~(cfg : Config.t) (record : Solution.Record.t) =
  let open RunAsync.Syntax in

  let doFetch path source =
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
      return `Done

    | Source.LocalPathLink _ ->
      (* this case is handled separately *)
      return `Done

    | Source.NoSource ->
      return `Done

    | Source.Archive {url; checksum}  ->
      let f tempPath =
        let%bind () = Fs.createDir tempPath in
        let tarballPath = Path.(tempPath / Filename.basename url) in
        match%lwt Curl.download ~output:tarballPath url with
        | Ok () ->
          let%bind () = Checksum.checkFile ~path:tarballPath checksum in
          let%bind () = Tarball.unpack ~stripComponents:1 ~dst:path tarballPath in
          return `Done
        | Error err -> return (`TryNext err)
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
        return `Done
      in
      Fs.withTempDir f

    | Source.Git git ->
      let%bind () = Git.clone ~dst:path ~remote:git.remote () in
      let%bind () = Git.checkout ~ref:git.commit ~repo:path () in
      let%bind () = Fs.rmPath Path.(path / ".git") in
      return `Done
  in

  let commit path source =

    let removeEsyJsonIfExists () =
      let esyJson = Path.(path / "esy.json") in
      match%bind Fs.exists(esyJson) with
      | true -> Fs.unlink(esyJson)
      | false -> return ()
    in

    let%bind () =
      match record.opam with
      | Some { name; version; opam; override } ->
        let%bind () = removeEsyJsonIfExists() in
        let data =
          Format.asprintf
            "name: \"%a\"\nversion: \"%a\"\n%a"
            Package.Opam.OpamName.pp name
            Package.Opam.OpamPackageVersion.pp version
            Package.Opam.OpamFile.pp opam
        in
        let%bind () = Fs.createDir Path.(path / "_esy") in
        let%bind () = Fs.writeFile ~data Path.(path / "_esy" / "opam") in
        let%bind () =
          let info = {
            EsyOpamFile.
            override;
            source;
          } in
          EsyOpamFile.toFile info Path.(path / "_esy" / "esy-opam.json")
        in
        return ()
      | None -> return ()
    in

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

  let doFetchIfNeeded source =
    let unsafeKey = cacheId source record in
    let key = EsyLib.Path.safePath unsafeKey in
    let tarballPath = Path.(cfg.cacheTarballsPath // v key |> addExt "tgz") in

    let dist = {
      Dist.
      tarballPath = Some tarballPath;
      name = record.name;
      version = record.version;
      source;
      override = record.override;
    } in
    let%bind tarballIsInCache = Fs.exists tarballPath in

    match source, tarballIsInCache with
    | Source.LocalPathLink _, _ ->
      return (`Done dist)
    | _, true ->
      return (`Done dist)
    | _, false ->
      Fs.withTempDir (fun sourcePath ->
        let%bind fetched =
          RunAsync.contextf (
            let%bind () = Fs.createDir sourcePath in
            match%bind doFetch sourcePath source with
            | `Done ->
              let%bind () = commit sourcePath source in
              return `Done
            | `TryNext err -> return (`TryNext err)
          )
          "fetching %a" Source.pp source
        in

        match fetched with
        | `Done ->
          let%bind () =
            let%bind () = Fs.createDir (Path.parent tarballPath) in
            let tempTarballPath = Path.(tarballPath |> addExt ".tmp") in
            let%bind () = Tarball.create ~filename:tempTarballPath sourcePath in
            let%bind () = Fs.rename ~src:tempTarballPath tarballPath in
            return ()
          in
          return (`Done dist)
        | `TryNext err -> return (`TryNext err)
      )
    in

    let rec tryFetch errs sources =
      match sources with
      | source::nextSources ->
        begin match%bind doFetchIfNeeded source with
        | `Done dist -> return dist
        | `TryNext err ->
          tryFetch ((source, err)::errs) nextSources
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

    tryFetch [] sources

let install ~cfg:_ ~path dist =
  let open RunAsync.Syntax in
  let {Dist. tarballPath; source; override; _} = dist in

  let%bind () = Fs.createDir path in

  let%bind () =
    match source, tarballPath with
    | Source.LocalPathLink _, _
    | _, None ->
      return ()
    | _, Some tarballPath ->
      Tarball.unpack ~dst:path tarballPath
  in

  let%bind () =
    EsyLinkFile.toDir
      EsyLinkFile.{source; override;}
      path
  in

  return ()
