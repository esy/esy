module Config = Shared.Config
module Solution = Shared.Solution
module Lockfile = Shared.Lockfile
module Files = Shared.Files
module Wget = Shared.Wget
module ExecCommand = Shared.ExecCommand

module Package = struct
  type t = {
    name : string;
    version : Lockfile.realVersion;
    source : Solution.Source.t;
    path : Path.t;
  }
end

type pkg = Package.t

let fetch ~(config : Config.t) ~name ~version ~source =
  let open RunAsync.Syntax in

  let info, opamFile = source in

  let doFetch path =
    match info with
    | Solution.Source.File _ -> failwith "NOT IMPLEMENTED"
    | Solution.Source.NoSource ->
      let%bind () = Fs.createDirectory path in
      return ()

    | Solution.Source.Archive (url, _checksum)  ->
      let safe = Str.global_replace (Str.regexp "/") "-" name in
      let withVersion = safe ^ (Lockfile.viewRealVersion version) in
      let tarball = Path.(config.Config.tarballCachePath / (withVersion ^ ".tarball")) in

      if not (Files.isFile (Path.toString tarball)) then
        Wget.download ~output:tarball url
        |> RunAsync.runExn ~err:"error downloading archive"
      ;

      Tarball.unpack ~stripComponents:1 ~dst:path ~filename:tarball
      |> RunAsync.runExn ~err:"error unpacking";

      return ()

    | Solution.Source.GithubSource (user, repo, ref) ->
      let safe =
        Str.global_replace
          (Str.regexp "/")
          "-"
          (name ^ "__" ^ user ^ "__" ^ repo ^ "__" ^ ref)
      in
      let tarball = Path.(config.tarballCachePath / (safe ^ ".tarball")) in
      if not (Files.isFile (Path.toString tarball)) then (
        let tarUrl =
          "https://api.github.com/repos/"
          ^ user
          ^ "/"
          ^ repo
          ^ "/tarball/"
          ^ ref
        in
        Wget.download ~output:tarball tarUrl
        |> RunAsync.runExn ~err:"error downloading archive"
      );

      Tarball.unpack ~stripComponents:1 ~dst:path ~filename:tarball
      |> RunAsync.runExn ~err:"error unpacking";

      return ()

    | Solution.Source.GitSource (gitUrl, commit) ->
      let safe = Str.global_replace (Str.regexp "/") "-" name in
      let withVersion = safe ^ (Lockfile.viewRealVersion version) in
      let tarball = Path.(config.tarballCachePath / (withVersion ^ ".tarball")) in

      if not (Files.isFile (Path.toString tarball)) then (
        let gitdest = Path.(config.tarballCachePath / ("git-" ^ withVersion)) in

        Git.clone ~dst:gitdest ~remote:gitUrl
        |> RunAsync.runExn ~err:"error cloning repo";

        Git.checkout ~ref:commit ~repo:gitdest
        |> RunAsync.runExn ~err:"error checkouting ref";

        ChildProcess.run Cmd.(v "rm" % "-rf" % p Path.(gitdest / ".git"))
        |> RunAsync.runExn ~err:"error checkouting ref";

        Tarball.create ~src:gitdest ~filename:tarball
        |> RunAsync.runExn ~err:"error creating archive";

        ChildProcess.run Cmd.(v "mv" % p gitdest % p path)
        |> RunAsync.runExn ~err:"error moving directory";

      ) else (
        Tarball.unpack ~dst:path ~stripComponents:1 ~filename:tarball
        |> RunAsync.runExn ~err:"error extracting archive"
      );

      return ()
    in

    let complete path =

      let resolvedString name version =
        Shared.Types.resolvedPrefix ^ name ^ "--" ^ Lockfile.viewRealVersion version
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
      let version = Lockfile.viewRealVersion version in
      Printf.sprintf "%s__%s" name version
    in

    let stagePath = Path.(config.packageCachePath // v (key ^ "__stage")) in
    let finalPath = Path.(config.packageCachePath // v key) in

    let pkg = {Package. path = finalPath; name; version; source} in

    match%bind Fs.exists finalPath with
    | true ->
      return pkg
    | false ->
      let%bind () = Fs.createDirectory stagePath in
      let%bind () = doFetch stagePath in
      let%bind () = complete stagePath in
      let%bind () = Fs.rename ~source:stagePath finalPath in
      return pkg

let install ~config:_ ~dst pkg =
  let open RunAsync.Syntax in
  let {Package. path; _} = pkg in
  let%bind () = Fs.createDirectory (Path.parent dst) in
  let%bind () = Fs.symlink ~source:path dst in
  return ()
