
module Package = struct
  type t = {
    name : string;
    version : Solution.Version.t;
    source : Solution.Source.t;
    tarballPath : Path.t;
  }
end

type pkg = Package.t

let fetch ~(config : Config.t) {Solution. name; version; source; _} =
  let open RunAsync.Syntax in

  let info, opamFile = source in

  let doFetch path =
    match info with
    | Solution.Source.File _ ->
      failwith "NOT IMPLEMENTED"

    | Solution.Source.NoSource ->
      return ()

    | Solution.Source.Archive (url, _checksum)  ->
      let f tempPath =
        let%bind () = Fs.createDirectory tempPath in
        let tarballPath = Path.(tempPath / "package.tgz") in
        let%bind () = Curl.download ~output:tarballPath url in
        let%bind () = Tarball.unpack ~stripComponents:1 ~dst:path tarballPath in
        return ()
      in
      Fs.withTempDir f

    | Solution.Source.GithubSource (user, repo, ref) ->
      let f tempPath =
        let%bind () = Fs.createDirectory tempPath in
        let tarballPath = Path.(tempPath / "package.tgz") in
        let%bind () =
          let url =
            Printf.sprintf
              "https://api.github.com/repos/%s/%s/tarball/%s"
              user repo ref
          in
          Curl.download ~output:tarballPath url
        in
        let%bind () =  Tarball.unpack ~stripComponents:1 ~dst:path tarballPath in
        return ()
      in
      Fs.withTempDir f

    | Solution.Source.GitSource (gitUrl, commit) ->
      let%bind () = Git.clone ~dst:path ~remote:gitUrl in
      let%bind () = Git.checkout ~ref:commit ~repo:path in
      let%bind _ = Fs.rmPath Path.(path / ".git") in
      return ()
    in

    let complete path =

      let resolvedString name version =
        Types.resolvedPrefix ^ name ^ "--" ^ Solution.Version.toString version
      in

      let removeEsyJsonIfExists () =
        let esyJson = Path.(path / "esy.json") in
        match%bind Fs.exists(esyJson) with
        | true -> Fs.unlink(esyJson)
        | false -> return ()
      in

      let addResolvedFieldToPackageJson filename name version =
        match%bind Fs.readJsonFile filename with
        | `Assoc items ->
          let json = `Assoc (("_resolved", `String (resolvedString name version))::items) in
          let data = Yojson.Safe.pretty_to_string json in
          Fs.writeFile ~data filename
        | _ -> error "invalid package.json"
      in

      match opamFile with
      | Some (packageJson, files, patches) ->

        let%bind () = removeEsyJsonIfExists() in

        let%bind () =
          Fs.writeJsonFile ~json:packageJson Path.(path / "package.json")
        in

        let%bind () =
          let f (name, data) =
            let name = Path.append path (Path.v name) in
            let dirname = Path.parent name in
            let%bind () = Fs.createDirectory dirname in
            let%bind () = Fs.writeFile ~data name in
            return()
          in
          List.map f files |> RunAsync.List.waitAll
        in

        patches
        |> List.iter(fun abspath ->
            ExecCommand.execStringSync
              ~cmd:(Printf.sprintf
                  "sh -c 'cd %s && patch -p1 < %s'"
                  (Path.toString path)
                  abspath)
              ()
            |> snd
            |> Files.expectSuccess("Failed to patch")
        );
        return()

      | None ->
        let packageJson = Path.(path / "package.json") in
        if%bind Fs.exists(packageJson) then
          addResolvedFieldToPackageJson packageJson name version
        else
          error "No opam file or package.json"
    in

    let key =
      let version = Solution.Version.toString version in
      Printf.sprintf "%s__%s" name version
    in

    let tarballPath = Path.(config.tarballCachePath // v (key ^ ".tgz")) in

    let pkg = {Package. tarballPath; name; version; source} in

    match%bind Fs.exists tarballPath with
    | true ->
      return pkg
    | false ->
      Fs.withTempDir (fun sourcePath ->
        let%bind () =
          let%bind () = Fs.createDirectory sourcePath in
          Logs.app (fun m -> m "Fetching %s" name);
          let%bind () = doFetch sourcePath in
          let%bind () = complete sourcePath in
          Logs.app (fun m -> m "Fetching %s: done" name);
          return ()
        in

        let%bind () =
          let%bind () = Fs.createDirectory (Path.parent tarballPath) in
          let tempTarballPath = Path.(tarballPath |> addExt ".tmp") in
          let%bind () = Tarball.create ~filename:tempTarballPath sourcePath in
          let%bind () = Fs.rename ~source:tempTarballPath tarballPath in
          return ()
        in

        return pkg
      )

let install ~config:_ ~dst pkg =
  let open RunAsync.Syntax in
  let {Package. tarballPath; _} = pkg in
  let%bind () = Fs.createDirectory dst in
  let%bind () = Tarball.unpack ~dst tarballPath in
  return ()
