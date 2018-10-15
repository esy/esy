module Overrides = Package.Overrides
module Package = Solution.Package
module Dist = FetchStorage.Dist

module PackageJson = struct

  module Scripts = struct
    type t = {
      postinstall : (string option [@default None]);
      install : (string option [@default None]);
    }
    [@@deriving of_yojson { strict = false }]

    let empty = {postinstall = None; install = None}
  end

  module Bin = struct
    type t =
      | Empty
      | One of string
      | Many of string StringMap.t

    let of_yojson =
      let open Result.Syntax in
      function
      | `String cmd ->
        let cmd = String.trim cmd in
        begin match cmd with
        | "" -> return Empty
        | cmd -> return (One cmd)
        end
      | `Assoc items ->
        let%bind items =
          let f cmds (name, json) =
            match json with
            | `String cmd -> return (StringMap.add name cmd cmds)
            | _ -> error "expected a string"
          in
          Result.List.foldLeft ~f ~init:StringMap.empty items
        in
        return (Many items)
      | _ -> error "expected a string or an object"
  end

  type t = {
    name : string;
    bin : (Bin.t [@default Bin.Empty]);
    scripts : (Scripts.t [@default Scripts.empty]);
    esy : (Json.t option [@default None]);
  } [@@deriving of_yojson { strict = false }]

  let ofDir path =
    let open RunAsync.Syntax in
    let filename = Path.(path / "package.json") in
    if%bind Fs.exists filename
    then
      let%bind json = Fs.readJsonFile filename in
      let%bind manifest = RunAsync.ofRun (Json.parseJsonWith of_yojson json) in
      return (Some manifest)
    else
      return None

  let packageCommands (sourcePath : Path.t) manifest =
    let makePathToCmd cmdPath = Path.(sourcePath // v cmdPath |> normalize) in
    match manifest.bin with
    | Bin.One cmd ->
      [manifest.name, makePathToCmd cmd]
    | Bin.Many cmds ->
      let f name cmd cmds = (name, makePathToCmd cmd)::cmds in
      (StringMap.fold f cmds [])
    | Bin.Empty -> []

end

module Install = struct

  type t = {
    path : Path.t;
    sourcePath : Path.t;
    pkg : Package.t;
    isDirectDependencyOfRoot : bool;
    status: FetchStorage.status;
  }

  let pp fmt installation =
    Fmt.pf fmt "%a at %a"
      Package.pp installation.pkg
      Path.pp installation.path
end

(*
 * This describes the physical layout of a solution on filesystem.
 *
 * TODO: redesign to allow safe parallel operations - no it's a plain list but
 * maybe we need a nested structure so that different installation do not race
 * with each other. Though the current method of installation (tar xzf) doesn't
 * uncover any issues with that yet.
 *)
module Layout = struct

  type t = Install.t list

  let pp =
    Fmt.(list ~sep:(unit "@\n") Install.pp)

  let ofSolution ~nodeModulesPath sandboxPath (sol : Solution.t) =
    let root = Solution.root sol in
      let isDirectDependencyOfRoot =
        let directDependencies =
          let deps = Solution.dependencies root sol in
          Package.Set.of_list deps
        in
        fun pkg -> Package.Set.mem pkg directDependencies
      in

      (* Go through breadcrumb till the insertion point and mark each modules as
       * occupied for the pkg. This will prevent inserting other versions of
       * the same pkg at such places. *)
      let markAsOccupied insertion breadcrumb pkg =
        let _, insertionPath = insertion in
        let rec aux = function
          | (modules, path)::rest ->
            Hashtbl.replace modules pkg.Package.name pkg;
            if Path.compare insertionPath path = 0
            then ()
            else aux rest
          | [] -> ()
        in
        aux breadcrumb
      in

      let rec findInsertion pkg breacrumb =
        match breacrumb with
        | [] -> `None
        | ((modules, _) as here)::upTheTree ->
          begin match Hashtbl.find_opt modules pkg.Package.name with
          | Some r ->
            if Package.compare r pkg = 0
            then `Done (here, here::upTheTree)
            else `None
          | None ->
            begin match findInsertion pkg upTheTree with
            | `Ok nextItem -> `Ok nextItem
            | `Done there -> `Done there
            | `None -> `Ok (here, here::upTheTree)
            end
          end
      in

      (* layout pkg at breadcrumb, return layout and a new breadcrumb which
       * is then used to layout pkg's dependencies *)
      let layoutPkg ~this ~breadcrumb ~layout pkg =

        let insert ((_modules, path) as here) =
          markAsOccupied here (this::breadcrumb) pkg;
          let path = Path.(path // v pkg.Package.name) in
          let sourcePath =
            let main, _ = pkg.Package.source in
            match main with
            | Source.Archive _
            | Source.Git _
            | Source.Github _
            | Source.LocalPath _
            | Source.NoSource -> path
            | Source.LocalPathLink {path; manifest = _;} -> Path.(sandboxPath // path)
          in
          let installation = {
            Install.
            path;
            sourcePath;
            pkg;
            isDirectDependencyOfRoot = isDirectDependencyOfRoot pkg;
            status = FetchStorage.Fresh;
          } in
          installation::layout
        in

        match findInsertion pkg breadcrumb with
        | `Done (there, _) ->
          markAsOccupied there (this::breadcrumb) pkg;
          None
        | `Ok (here, breadcrumb) ->
          Some (insert here, breadcrumb)
        | `None ->
          Some (insert this, this::breadcrumb)
      in

      let rec layoutDependencies ~seen ~breadcrumb ~layout pkg =

        let this =
          let modules = Hashtbl.create 100 in
          let path =
            match breadcrumb with
            | (_modules, path)::_ -> Path.(path // v pkg.Package.name / "node_modules")
            | [] -> nodeModulesPath
          in
          modules, path
        in

        let dependencies = Solution.dependencies pkg sol in

        (* layout direct dependencies first, they can be relocated so this is
         * why get dependenciesWithBreadcrumbs as a result *)
        let layout, dependenciesWithBreadcrumbs =
          let f (layout, dependenciesWithBreadcrumbs) r =
            match layoutPkg ~this ~breadcrumb ~layout r with
            | Some (layout, breadcrumb) -> layout, (r, breadcrumb)::dependenciesWithBreadcrumbs
            | None -> layout, dependenciesWithBreadcrumbs
          in
          List.fold_left ~f ~init:(layout, []) dependencies
        in

        (* now layout dependencies of dependencies *)
        let layout =
          let seen = Package.Set.add pkg seen in
          let f layout (r, breadcrumb) =
              match Package.Set.mem r seen with
              | true -> layout
              | false -> layoutDependencies ~seen ~breadcrumb ~layout r
          in
          List.fold_left ~f ~init:layout dependenciesWithBreadcrumbs
        in

        layout
      in

      let layout =
        layoutDependencies ~seen:Package.Set.empty ~breadcrumb:[] ~layout:[] root
      in

      (* Sort the layout so we can have stable order of operations *)
      let layout =
        let cmp a b = Path.compare a.Install.path b.Install.path in
        List.sort ~cmp layout
      in

      (layout : t)

  let%test_module "Layout" = (module struct

    let parseVersionExn v =
      match SemverVersion.Version.parse v with
      | Ok v -> v
      | Error msg -> failwith msg

    let r name version dependencies = ({
      Package.
      name;
      version = Version.Npm (parseVersionExn version);
      source = Source.NoSource, [];
      overrides = Overrides.empty;
      dependencies = PackageId.Set.of_list dependencies;
      devDependencies = PackageId.Set.empty;
      files = [];
      opam = None;
    } : Package.t)

    let id name version =
      let version = version ^ ".0.0" in
      let version = Version.Npm (parseVersionExn version) in
      PackageId.make name version

    let addToSolution pkg =
      Solution.add pkg

    let expect layout expectation =
      let convert =
        let f (installation : Install.t) =
          Format.asprintf "%a" Package.pp installation.Install.pkg,
          Path.show installation.Install.path
        in
        List.map ~f layout
      in
      if Pervasives.compare convert expectation = 0
      then true
      else begin
        Format.printf "Got:@[<v 2>@\n%a@]@\n" pp layout;
        false
      end

    let%test "simple" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "a" "1" [])
        |> addToSolution (r "b" "1" [])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
      ]

    let%test "simple2" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "a" "1" [])
        |> addToSolution (r "b" "1" [id "a" "1"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
      ]

    let%test "simple3" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "c" "1" [])
        |> addToSolution (r "a" "1" [id "c" "1"])
        |> addToSolution (r "b" "1" [id "c" "1"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
        "c@1.0.0", "./node_modules/c";
      ]

    let%test "conflict" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "a" "1" [])
        |> addToSolution (r "a" "2" [])
        |> addToSolution (r "b" "1" [id "a" "2"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
        "a@2.0.0", "./node_modules/b/node_modules/a";
      ]

    let%test "conflict2" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "shared" "1" [])
        |> addToSolution (r "a" "1" [id "shared" "1"])
        |> addToSolution (r "a" "2" [id "shared" "1"])
        |> addToSolution (r "b" "1" [id "a" "2"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
        "a@2.0.0", "./node_modules/b/node_modules/a";
        "shared@1.0.0", "./node_modules/shared";
      ]

    let%test "conflict3" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "shared" "1" [])
        |> addToSolution (r "shared" "2" [])
        |> addToSolution (r "a" "1" [id "shared" "1"])
        |> addToSolution (r "a" "2" [id "shared" "2"])
        |> addToSolution (r "b" "1" [id "a" "2"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "shared@1.0.0", "./node_modules/a/node_modules/shared";
        "b@1.0.0", "./node_modules/b";
        "a@2.0.0", "./node_modules/b/node_modules/a";
        "shared@2.0.0", "./node_modules/shared";
      ]

    let%test "conflict4" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "c" "1" [])
        |> addToSolution (r "c" "2" [])
        |> addToSolution (r "a" "1" [id "c" "1"])
        |> addToSolution (r "b" "1" [id "c" "2"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "c@1.0.0", "./node_modules/a/node_modules/c";
        "b@1.0.0", "./node_modules/b";
        "c@2.0.0", "./node_modules/c";
      ]

    let%test "nested" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "d" "1" [])
        |> addToSolution (r "c" "1" [id "d" "1"])
        |> addToSolution (r "a" "1" [id "c" "1"])
        |> addToSolution (r "b" "1" [id "c" "1"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
        "c@1.0.0", "./node_modules/c";
        "d@1.0.0", "./node_modules/d";
      ]

    let%test "nested conflict" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "d" "1" [])
        |> addToSolution (r "c" "1" [id "d" "1"])
        |> addToSolution (r "c" "2" [id "d" "1"])
        |> addToSolution (r "a" "1" [id "c" "1"])
        |> addToSolution (r "b" "1" [id "c" "2"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "c@1.0.0", "./node_modules/a/node_modules/c";
        "b@1.0.0", "./node_modules/b";
        "c@2.0.0", "./node_modules/c";
        "d@1.0.0", "./node_modules/d";
      ]

    let%test "nested conflict 2" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "d" "1" [])
        |> addToSolution (r "d" "2" [])
        |> addToSolution (r "c" "1" [id "d" "1"])
        |> addToSolution (r "c" "2" [id "d" "2"])
        |> addToSolution (r "a" "1" [id "c" "1"])
        |> addToSolution (r "b" "1" [id "c" "2"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "c@1.0.0", "./node_modules/a/node_modules/c";
        "d@1.0.0", "./node_modules/a/node_modules/d";
        "b@1.0.0", "./node_modules/b";
        "c@2.0.0", "./node_modules/c";
        "d@2.0.0", "./node_modules/d";
      ]

    let%test "nested conflict 3" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "d" "1" [])
        |> addToSolution (r "d" "2" [])
        |> addToSolution (r "b" "1" [id "d" "1"])
        |> addToSolution (r "a" "1" [id "b" "1"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "d" "2"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
        "d@1.0.0", "./node_modules/b/node_modules/d";
        "d@2.0.0", "./node_modules/d";
      ]

    let%test "nested conflict 4" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "d" "1" [])
        |> addToSolution (r "c" "1" [id "d" "1"])
        |> addToSolution (r "c" "2" [id "d" "1"])
        |> addToSolution (r "b" "1" [id "c" "2"])
        |> addToSolution (r "a" "1" [id "c" "1"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "c@1.0.0", "./node_modules/a/node_modules/c";
        "b@1.0.0", "./node_modules/b";
        "c@2.0.0", "./node_modules/c";
        "d@1.0.0", "./node_modules/d";
      ]

    let%test "nested conflict 5" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "d" "1" [])
        |> addToSolution (r "d" "2" [])
        |> addToSolution (r "c" "1" [id "d" "1"])
        |> addToSolution (r "c" "2" [id "d" "2"])
        |> addToSolution (r "b" "1" [id "c" "2"])
        |> addToSolution (r "a" "1" [id "c" "1"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "c@1.0.0", "./node_modules/a/node_modules/c";
        "d@1.0.0", "./node_modules/a/node_modules/d";
        "b@1.0.0", "./node_modules/b";
        "c@2.0.0", "./node_modules/c";
        "d@2.0.0", "./node_modules/d";
      ]

    let%test "nested conflict 6" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "punycode" "1" [])
        |> addToSolution (r "punycode" "2" [])
        |> addToSolution (r "url" "1" [id "punycode" "2"])
        |> addToSolution (r "browserify" "1" [id "punycode" "1"; id "url" "1"])
        |> addToSolution (r "root" "1" [id "browserify" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "browserify@1.0.0", "./node_modules/browserify";
        "punycode@1.0.0", "./node_modules/punycode";
        "url@1.0.0", "./node_modules/url";
        "punycode@2.0.0", "./node_modules/url/node_modules/punycode";
      ]

    let%test "loop 1" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "b" "1" [id "a" "1"])
        |> addToSolution (r "a" "1" [id "b" "1"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
      ]

    let%test "loop 2" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "c" "1" [])
        |> addToSolution (r "b" "1" [id "a" "1"; id "c" "1"])
        |> addToSolution (r "a" "1" [id "b" "1"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
        "c@1.0.0", "./node_modules/c";
      ]

    let%test "loop 3" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "c" "1" [id "a" "1"])
        |> addToSolution (r "b" "1" [id "a" "1"])
        |> addToSolution (r "a" "1" [id "b" "1"; id "c" "1"])
        |> addToSolution (r "root" "1" [id "a" "1"; id "b" "1"])
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
        "c@1.0.0", "./node_modules/c";
      ]

  end)
end

let runLifecycleScript ?env ~install ~lifecycleName script =
  let%lwt () = Logs_lwt.debug
    (fun m ->
      m "Fetch.runLifecycleScript ~env:%a ~pkg:%a ~lifecycleName:%s"
      (Fmt.option ChildProcess.pp_env) env
      Package.pp install.Install.pkg
      lifecycleName
    )
  in

  let%lwt () = Logs_lwt.app
    (fun m ->
      m "%a: running %a lifecycle"
      Package.pp install.Install.pkg
      Fmt.(styled `Bold string) lifecycleName
    )
  in

  let readAndCloseChan ic =
    Lwt.finalize
      (fun () -> Lwt_io.read ic)
      (fun () -> Lwt_io.close ic)
  in

  let f p =
    let%lwt stdout = readAndCloseChan p#stdout
    and stderr = readAndCloseChan p#stderr in
    match%lwt p#status with
    | Unix.WEXITED 0 ->
      RunAsync.return ()
    | _ ->
      Logs_lwt.err (fun m -> m
        "@[<v>command failed: %s@\nstderr:@[<v 2>@\n%s@]@\nstdout:@[<v 2>@\n%s@]@]"
        script stderr stdout
      );%lwt
      RunAsync.error "error running command"
  in

  try%lwt
    (* We don't need to wrap the install path on Windows in quotes *)
    let installationPath =
      match System.Platform.host with
      | Windows -> Path.show install.path
      | _ -> Filename.quote (Path.show install.path)
    in
    let script =
      Printf.sprintf
        "cd %s && %s"
        installationPath
        script
    in
    let cmd =
      match System.Platform.host with
      | Windows -> ("", [|"cmd.exe";("/c " ^ script)|])
      | _ -> ("/bin/bash", [|"/bin/bash";"-c";script|])
    in
    let env =
      let open Option.Syntax in
      let%bind env = env in
      let%bind _, env = ChildProcess.prepareEnv env in
      return env
    in
    Lwt_process.with_process_full ?env cmd f
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    RunAsync.error msg
  | _ ->
    RunAsync.error "error running subprocess"

let runLifecycle ?env ~install ~(pkgJson : PackageJson.t) () =
  let open RunAsync.Syntax in
  let%bind () =
    match pkgJson.scripts.install with
    | Some cmd -> runLifecycleScript ?env ~install ~lifecycleName:"install" cmd
    | None -> return ()
  in
  let%bind () =
    match pkgJson.scripts.postinstall with
    | Some cmd -> runLifecycleScript ?env ~install ~lifecycleName:"postinstall" cmd
    | None -> return ()
  in
  return ()

let isInstalled ~(sandbox : Sandbox.t) (solution : Solution.t) =
  let open RunAsync.Syntax in
  let nodeModulesPath = SandboxSpec.nodeModulesPath sandbox.spec in
  let layout = Layout.ofSolution ~nodeModulesPath sandbox.spec.path solution in
  let f installed {Install. path;_} =
    if not installed
    then return installed
    else Fs.exists path
  in
  RunAsync.List.foldLeft ~f ~init:true layout

let fetchNodeModules ~(sandbox : Sandbox.t) (solution : Solution.t) =
  let open RunAsync.Syntax in

  (* Collect packages which from the solution *)
  let nodeModulesPath = SandboxSpec.nodeModulesPath sandbox.spec in

  let%bind () = Fs.rmPath nodeModulesPath in
  let%bind () = Fs.createDir nodeModulesPath in

  let pkgs =
    let root = Solution.root solution in
    let all =
      let f pkg _ pkgs = Package.Set.add pkg pkgs in
      Solution.fold ~f ~init:Package.Set.empty solution
    in
    Package.Set.remove root all
  in

  (* Fetch all pkgs *)

  let%bind dists =
    let queue = LwtTaskQueue.create ~concurrency:8 () in
    let report, finish = Cli.createProgressReporter ~name:"fetching" () in
    let%bind items =
      let fetch pkg =
        let%bind dist =
          LwtTaskQueue.submit queue
          (fun () ->
            let%lwt () =
              let status = Format.asprintf "%a" Package.pp pkg in
              report status
            in
            FetchStorage.fetch ~sandbox pkg)
        in
        return (pkg, dist)
      in
      pkgs
      |> Package.Set.elements
      |> List.map ~f:fetch
      |> RunAsync.List.joinAll
    in
    let%lwt () = finish () in
    let map =
      let f map (pkg, dist) = Package.Map.add pkg dist map in
      List.fold_left ~f ~init:Package.Map.empty items
    in
    return map
  in

  (* Layout all dists into node_modules *)

  let%bind installed =
    let queue = LwtTaskQueue.create ~concurrency:4 () in
    let report, finish = Cli.createProgressReporter ~name:"installing" () in
    let f ({Install. path; sourcePath;pkg;_} as install) () =
      match Package.Map.find_opt pkg dists with
      | Some dist ->
        let%lwt () =
          let status = Format.asprintf "%a" Dist.pp dist in
          report status
        in
        let%bind () =
          FetchStorage.installNodeModules ~sandbox ~path dist
        in
        let%bind manifest = PackageJson.ofDir sourcePath in
        return (install, manifest)
      | None ->
        let msg =
          Printf.sprintf
            "inconsistent state: no dist were fetched for %s@%s at %s"
            pkg.Package.name
            (Version.show pkg.Package.version)
            (Path.show path)
        in
        failwith msg
    in

    let layout =
      Layout.ofSolution
        ~nodeModulesPath
        sandbox.spec.path
        solution
    in

    let%bind installed =
      let install install =
        RunAsync.contextf
          (LwtTaskQueue.submit queue (f install))
          "installing %a"
          Install.pp install
      in
      layout
      |> List.map ~f:install
      |> RunAsync.List.joinAll
    in

    let%lwt () = finish () in

    return installed
  in

  (* run lifecycle scripts *)

  let%bind () =
    let queue = LwtTaskQueue.create ~concurrency:1 () in

    let f = function
      | (install, Some ({PackageJson. esy = None; _} as pkgJson)) ->
        RunAsync.contextf
          (LwtTaskQueue.submit
            queue
            (runLifecycle
              ~install
              ~pkgJson))
          "running lifecycle %a"
          Install.pp install
      | (_install, Some {PackageJson. esy = Some _; _})
      | (_install, None) -> return ()
    in

    let%bind () =
      installed
      |> List.map ~f
      |> RunAsync.List.waitAll
    in

    return ()
  in

  (* populate node_modules/.bin with scripts defined for the direct dependencies *)

  let%bind () =
    let nodeModulesPath = SandboxSpec.nodeModulesPath sandbox.spec in
    let binPath = Path.(nodeModulesPath / ".bin") in
    let%bind () = Fs.createDir binPath in

    let installBinWrapper (name, path) =
      if%bind Fs.exists path
      then (
        let%bind () = Fs.chmod 0o777 path in
        Fs.symlink ~src:path Path.(binPath / name)
      ) else (
        Logs_lwt.warn (fun m -> m "missing %a defined as binary" Path.pp path);%lwt
        return ()
      )
    in

    let installBinWrappersForPkg = function
      | (installation, Some manifest) ->
        PackageJson.packageCommands installation.Install.sourcePath manifest
        |> List.map ~f:installBinWrapper
        |> RunAsync.List.waitAll
      | (_installation, None) -> return ()
    in

    installed
    |> List.filter ~f:(fun (installation, _) -> installation.Install.isDirectDependencyOfRoot)
    |> List.map ~f:installBinWrappersForPkg
    |> RunAsync.List.waitAll
  in

  (* link default sandbox node_modules to <projectPath>/node_modules *)

  let%bind () =
    if SandboxSpec.isDefault sandbox.spec
    then
      let nodeModulesPath = SandboxSpec.nodeModulesPath sandbox.spec in
      let targetPath = Path.(sandbox.spec.path / "node_modules") in
      let%bind () = Fs.rmPath targetPath in
      let%bind () = Fs.symlink ~src:nodeModulesPath targetPath in
      return ()
    else return ()
  in

  (* place dune with ignored_subdirs stanza inside node_modiles *)

  let%bind () =
    let packagesPath = SandboxSpec.nodeModulesPath sandbox.spec in
    let%bind items = Fs.listDir packagesPath in
    let items = String.concat " " items in
    let data = "(ignored_subdirs (" ^ items ^ "))\n" in
    Fs.writeFile ~data Path.(packagesPath / "dune")
  in

  return ()

let fetch ~(sandbox : Sandbox.t) (solution : Solution.t) =
  let open RunAsync.Syntax in

  (* Collect packages which from the solution *)
  let nodeModulesPath = SandboxSpec.nodeModulesPath sandbox.spec in

  let%bind () = Fs.rmPath nodeModulesPath in
  let%bind () = Fs.createDir nodeModulesPath in

  let%bind pkgs, root =
    let root = Solution.root solution in
    let all =
      let f pkg _ pkgs = Package.Set.add pkg pkgs in
      Solution.fold ~f ~init:Package.Set.empty solution
    in
    return (Package.Set.remove root all, root)
  in

  let directDependenciesOfRoot =
    let deps = Solution.dependencies root solution in
    Package.Set.of_list deps
  in

  (* Fetch all package distributions *)
  let%bind dists =
    let queue = LwtTaskQueue.create ~concurrency:8 () in
    let report, finish = Cli.createProgressReporter ~name:"fetching" () in

    let%bind dists =
      let fetch pkg () =
        let%lwt () =
          let status = Format.asprintf "%a" Package.pp pkg in
          report status
        in
        let%bind dist = FetchStorage.fetch ~sandbox pkg in
        let%bind status, path = FetchStorage.install ~sandbox dist in
        Logs_lwt.debug (fun m ->
          m "fetched: %a -> %a" Package.pp pkg Path.pp path);%lwt
        let%bind pkgJson = PackageJson.ofDir path in
        let install = {
          Install.
          pkg;
          sourcePath = path;
          path;
          isDirectDependencyOfRoot = Package.Set.mem pkg directDependenciesOfRoot;
          status;
        } in
        let id = Dist.id dist in
        return (id, (dist, install, pkgJson))
      in
      pkgs
      |> Package.Set.elements
      |> List.map ~f:(fun pkg -> LwtTaskQueue.submit queue (fetch pkg))
      |> RunAsync.List.joinAll
    in
    let%lwt () = finish () in

    let dists =
      let f dists (id, v) = PackageId.Map.add id v dists in
      List.fold_left ~f ~init:PackageId.Map.empty dists
    in

    return dists
  in

  (* Run lifecycle scripts *)
  let%bind () =

    let queue = LwtTaskQueue.create ~concurrency:8 () in

    let%bind binPath =
      let binPath = SandboxSpec.binPath sandbox.spec in
      let%bind () = Fs.createDir binPath in
      return binPath
    in

    let env =
      let override =
        let path = (Path.show binPath)::System.Environment.path in
        let sep = System.Environment.sep ~name:"PATH" () in
        Astring.String.Map.(
          empty
          |> add "PATH" (String.concat sep path)
        )
      in
      ChildProcess.CurrentEnvOverride override
    in

    let installBinWrapper (name, origPath) =
      Logs_lwt.debug (fun m ->
        m "Fetch:installBinWrapper: %a / %s -> %a"
        Path.pp origPath name Path.pp binPath
      );%lwt
      if%bind Fs.exists origPath
      then (
        let%bind () = Fs.chmod 0o777 origPath in
        Fs.symlink ~src:origPath Path.(binPath / name)
      ) else (
        Logs_lwt.warn (fun m -> m "missing %a defined as binary" Path.pp origPath);%lwt
        return ()
      )
    in

    let process install pkgJson =
      let%bind () =
        Logs_lwt.debug (fun m -> m "Fetch:runLifecycle:%a" Package.pp install.Install.pkg);%lwt
        RunAsync.contextf
          (LwtTaskQueue.submit
            queue
            (runLifecycle
              ~env
              ~install
              ~pkgJson))
          "running lifecycle %a"
          Install.pp install

      in

      let%bind () =
        Logs_lwt.debug (fun m -> m "Fetch:installBinWrappers:%a" Package.pp install.Install.pkg);%lwt
        PackageJson.packageCommands install.Install.sourcePath pkgJson
        |> List.map ~f:installBinWrapper
        |> RunAsync.List.waitAll

      in

      return ()
    in

    let seen = ref Package.Set.empty in

    let rec visit pkg =
      if Package.Set.mem pkg !seen
      then return ()
      else (
        seen := Package.Set.add pkg !seen;
        let isRoot = Package.compare root pkg = 0 in
        let dependendencies =
          let traverse =
            if isRoot
            then Solution.traverseWithDevDependencies
            else Solution.traverse
          in
          Solution.dependencies ~traverse pkg solution
        in
        let%bind () =
          List.map ~f:visit dependendencies
          |> RunAsync.List.waitAll
        in

        match isRoot, PackageId.Map.find_opt (Solution.Package.id pkg) dists with
        | false, Some (
            _dist,
            ({status = FetchStorage.Fresh; _ } as install),
            Some ({PackageJson. esy = None; _} as pkgJson)
          ) ->
          process install pkgJson
        | false, Some (_, {status = FetchStorage.Cached;_}, _) -> return ()
        | false, Some (_, {status = FetchStorage.Fresh;_}, _) -> return ()
        | false, None -> errorf "dist not found: %a" Package.pp pkg
        | true, _ -> return ()
      )
    in

    visit root
  in

  (* Produce _esy/<sandbox>/installation.json *)
  let%bind installation =
    let installation =
      let f id (dist, install, _pkgJson) installation =
        let source =
          let source = Dist.source dist in
          match source with
          | Source.LocalPathLink {path; manifest} ->
            Installation.Link {path; manifest;}
          | _ -> Installation.Install {path = install.Install.sourcePath; source;}
        in
        Installation.add id source installation
      in
      let init =
        Installation.empty
        |> Installation.add
            (Package.id root)
            (Installation.Link {
              path = sandbox.spec.path;
              manifest = Some sandbox.spec.manifest
            })
      in
      PackageId.Map.fold f dists init
    in

    let%bind () =
      Fs.writeJsonFile
        ~json:(Installation.to_yojson installation)
        (SandboxSpec.installationPath sandbox.spec)
    in

    return installation
  in

  (* Produce _esy/<sandbox>/pnp.json *)
  let%bind () =
    let path = SandboxSpec.pnpJsPath sandbox.spec in
    let data = PnpJs.render ~solution ~installation ~sandbox:sandbox.spec () in
    Fs.writeFile ~data path
  in

  (* Produce _esy/<sandbox>/bin *)
  let%bind () =
    let path = SandboxSpec.pnpJsPath sandbox.spec in
    let data = PnpJs.render ~solution ~installation ~sandbox:sandbox.spec () in
    Fs.writeFile ~data path
  in

  return ()
