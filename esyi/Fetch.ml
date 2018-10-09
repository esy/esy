module Overrides = Package.Overrides
module Package = Solution.Package
module Dist = FetchStorage.Dist

module Manifest = struct

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

(*
 * This describes the physical layout of a solution on filesystem.
 *
 * TODO: redesign to allow safe parallel operations - no it's a plain list but
 * maybe we need a nested structure so that different installation do not race
 * with each other. Though the current method of installation (tar xzf) doesn't
 * uncover any issues with that yet.
 *)
module Layout = struct

  type t = installation list

  and installation = {
    path : Path.t;
    sourcePath : Path.t;
    pkg : Package.t;
    isDirectDependencyOfRoot : bool;
  }

  let pp_installation fmt installation =
    Fmt.pf fmt "%a at %a"
      Package.pp installation.pkg
      Path.pp installation.path

  let pp =
    Fmt.(list ~sep:(unit "@\n") pp_installation)

  let ofSolution ~nodeModulesPath sandboxPath (sol : Solution.t) =
    let root = Solution.root sol in
      let isDirectDependencyOfRoot =
        let directDependencies =
          let deps = Solution.dependencies root sol in
          let deps = StringMap.values deps in
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
            path;
            sourcePath;
            pkg;
            isDirectDependencyOfRoot = isDirectDependencyOfRoot pkg;
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
          let f _label r (layout, dependenciesWithBreadcrumbs) =
            match layoutPkg ~this ~breadcrumb ~layout r with
            | Some (layout, breadcrumb) -> layout, (r, breadcrumb)::dependenciesWithBreadcrumbs
            | None -> layout, dependenciesWithBreadcrumbs
          in
          StringMap.fold f dependencies (layout, [])
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
        let cmp a b = Path.compare a.path b.path in
        List.sort ~cmp layout
      in

      (layout : t)

  let%test_module "Layout" = (module struct

    let parseVersionExn v =
      match SemverVersion.Version.parse v with
      | Ok v -> v
      | Error msg -> failwith msg

    let r name version = ({
      Package.
      name;
      version = Version.Npm (parseVersionExn version);
      source = Source.NoSource, [];
      overrides = Overrides.empty;
      files = [];
      opam = None;
    } : Package.t)

    let id name version =
      let version = version ^ ".0.0" in
      let version = Version.Npm (parseVersionExn version) in
      PackageId.make name version

    let addToSolution pkg deps =
      let deps =
        let f deps id =
          let name = PackageId.name id in
          StringMap.add name id deps
        in
        List.fold_left ~f ~init:StringMap.empty deps
      in
      Solution.add pkg deps

    let expect layout expectation =
      let convert =
        let f (installation : installation) =
          Format.asprintf "%a" Package.pp installation.pkg,
          Path.show installation.path
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
        |> addToSolution (r "a" "1") []
        |> addToSolution (r "b" "1") []
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
      ]

    let%test "simple2" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "a" "1") []
        |> addToSolution (r "b" "1") [id "a" "1"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
      ]

    let%test "simple3" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "c" "1") []
        |> addToSolution (r "a" "1") [id "c" "1"]
        |> addToSolution (r "b" "1") [id "c" "1"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
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
        |> addToSolution (r "a" "1") []
        |> addToSolution (r "a" "2") []
        |> addToSolution (r "b" "1") [id "a" "2"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
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
        |> addToSolution (r "shared" "1") []
        |> addToSolution (r "a" "1") [id "shared" "1"]
        |> addToSolution (r "a" "2") [id "shared" "1"]
        |> addToSolution (r "b" "1") [id "a" "2"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
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
        |> addToSolution (r "shared" "1") []
        |> addToSolution (r "shared" "2") []
        |> addToSolution (r "a" "1") [id "shared" "1"]
        |> addToSolution (r "a" "2") [id "shared" "2"]
        |> addToSolution (r "b" "1") [id "a" "2"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
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
        |> addToSolution (r "c" "1") []
        |> addToSolution (r "c" "2") []
        |> addToSolution (r "a" "1") [id "c" "1"]
        |> addToSolution (r "b" "1") [id "c" "2"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
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
        |> addToSolution (r "d" "1") []
        |> addToSolution (r "c" "1") [id "d" "1"]
        |> addToSolution (r "a" "1") [id "c" "1"]
        |> addToSolution (r "b" "1") [id "c" "1"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
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
        |> addToSolution (r "d" "1") []
        |> addToSolution (r "c" "1") [id "d" "1"]
        |> addToSolution (r "c" "2") [id "d" "1"]
        |> addToSolution (r "a" "1") [id "c" "1"]
        |> addToSolution (r "b" "1") [id "c" "2"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
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
        |> addToSolution (r "d" "1") []
        |> addToSolution (r "d" "2") []
        |> addToSolution (r "c" "1") [id "d" "1"]
        |> addToSolution (r "c" "2") [id "d" "2"]
        |> addToSolution (r "a" "1") [id "c" "1"]
        |> addToSolution (r "b" "1") [id "c" "2"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
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
        |> addToSolution (r "d" "1") []
        |> addToSolution (r "d" "2") []
        |> addToSolution (r "b" "1") [id "d" "1"]
        |> addToSolution (r "a" "1") [id "b" "1"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "d" "2"]
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
        |> addToSolution (r "d" "1") []
        |> addToSolution (r "c" "1") [id "d" "1"]
        |> addToSolution (r "c" "2") [id "d" "1"]
        |> addToSolution (r "b" "1") [id "c" "2"]
        |> addToSolution (r "a" "1") [id "c" "1"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
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
        |> addToSolution (r "d" "1") []
        |> addToSolution (r "d" "2") []
        |> addToSolution (r "c" "1") [id "d" "1"]
        |> addToSolution (r "c" "2") [id "d" "2"]
        |> addToSolution (r "b" "1") [id "c" "2"]
        |> addToSolution (r "a" "1") [id "c" "1"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
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
        |> addToSolution (r "punycode" "1") []
        |> addToSolution (r "punycode" "2") []
        |> addToSolution (r "url" "1") [id "punycode" "2"]
        |> addToSolution (r "browserify" "1") [id "punycode" "1"; id "url" "1"]
        |> addToSolution (r "root" "1") [id "browserify" "1"]
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
        |> addToSolution (r "b" "1") [id "a" "1"]
        |> addToSolution (r "a" "1") [id "b" "1"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
      ]

    let%test "loop 2" =
      let sol = Solution.(
        empty (id "root" "1")
        |> addToSolution (r "c" "1") []
        |> addToSolution (r "b" "1") [id "a" "1"; id "c" "1"]
        |> addToSolution (r "a" "1") [id "b" "1"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
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
        |> addToSolution (r "c" "1") [id "a" "1"]
        |> addToSolution (r "b" "1") [id "a" "1"]
        |> addToSolution (r "a" "1") [id "b" "1"; id "c" "1"]
        |> addToSolution (r "root" "1") [id "a" "1"; id "b" "1"]
      ) in
      let layout = ofSolution ~nodeModulesPath:(Path.v "./node_modules") (Path.v ".") sol in
      expect layout [
        "a@1.0.0", "./node_modules/a";
        "b@1.0.0", "./node_modules/b";
        "c@1.0.0", "./node_modules/c";
      ]

  end)
end

let runLifecycleScript ~installation ~name script =
  let%lwt () = Logs_lwt.app
    (fun m ->
      m "%a: running %a lifecycle"
      Package.pp installation.Layout.pkg
      Fmt.(styled `Bold string) name
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
      | Windows -> Path.show installation.path
      | _ -> Filename.quote (Path.show installation.path)
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
    Lwt_process.with_process_full cmd f
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    RunAsync.error msg
  | _ ->
    RunAsync.error "error running subprocess"

let runLifecycle ~installation ~(manifest : Manifest.t) () =
  let open RunAsync.Syntax in
  let%bind () =
    match manifest.scripts.install with
    | Some cmd -> runLifecycleScript ~installation ~name:"install" cmd
    | None -> return ()
  in
  let%bind () =
    match manifest.scripts.postinstall with
    | Some cmd -> runLifecycleScript ~installation ~name:"postinstall" cmd
    | None -> return ()
  in
  return ()

let isInstalled ~(sandbox : Sandbox.t) (solution : Solution.t) =
  let open RunAsync.Syntax in
  let nodeModulesPath = SandboxSpec.nodeModulesPath sandbox.spec in
  let layout = Layout.ofSolution ~nodeModulesPath sandbox.spec.path solution in
  let f installed {Layout.path;_} =
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
            FetchStorage.fetch ~cfg:sandbox.cfg pkg)
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
    let f ({Layout.path; sourcePath;pkg;_} as installation) () =
      match Package.Map.find_opt pkg dists with
      | Some dist ->
        let%lwt () =
          let status = Format.asprintf "%a" Dist.pp dist in
          report status
        in
        let%bind () =
          FetchStorage.install ~cfg:sandbox.cfg ~path dist
        in
        let%bind manifest = Manifest.ofDir sourcePath in
        return (installation, manifest)
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
      let install installation =
        RunAsync.contextf
          (LwtTaskQueue.submit queue (f installation))
          "installing %a"
          Layout.pp_installation installation
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
      | (installation, Some ({Manifest. esy = None; _} as manifest)) ->
        RunAsync.contextf
          (LwtTaskQueue.submit
            queue
            (runLifecycle ~installation ~manifest))
          "running lifecycle %a"
          Layout.pp_installation installation
      | (_installation, Some {Manifest. esy = Some _; _})
      | (_installation, None) -> return ()
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
        Manifest.packageCommands installation.Layout.sourcePath manifest
        |> List.map ~f:installBinWrapper
        |> RunAsync.List.waitAll
      | (_installation, None) -> return ()
    in

    installed
    |> List.filter ~f:(fun (installation, _) -> installation.Layout.isDirectDependencyOfRoot)
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

  (* Fetch all pkgs *)

  let%bind dists =
    let queue = LwtTaskQueue.create ~concurrency:8 () in
    let report, finish = Cli.createProgressReporter ~name:"fetching" () in

    let fetch pkg () =
      let%lwt () =
        let status = Format.asprintf "%a" Package.pp pkg in
        report status
      in
      let%bind dist = FetchStorage.fetch ~cfg:sandbox.cfg pkg in
      let%bind path = FetchStorage.unpack ~cfg:sandbox.cfg dist in
      return (dist, path)
    in
    let%bind dists =
      pkgs
      |> Package.Set.elements
      |> List.map ~f:(fun pkg -> LwtTaskQueue.submit queue (fetch pkg))
      |> RunAsync.List.joinAll
    in
    let%lwt () = finish () in
    return dists
  in

  let installation =
    let installation =
      Installation.empty
      |> Installation.add
          (Package.id root)
          (Installation.Link {path = sandbox.spec.path; manifest = None;})
    in
    let f installation (dist, sourcePath) =
      let source =
        let source = Dist.source dist in
        match source with
        | Source.LocalPathLink {path; manifest} ->
          Installation.Link {path; manifest;}
        | _ -> Installation.Install {path = sourcePath; source;}
      in
      Installation.add (Dist.id dist) source installation
    in
    List.fold_left ~f ~init:installation dists
  in

  let%bind () =
    Fs.writeJsonFile
      ~json:(Installation.to_yojson installation)
      (SandboxSpec.installationPath sandbox.spec)
  in

  let%bind () =
    let path = SandboxSpec.pnpJsPath sandbox.spec in
    let data = PnpJs.render ~solution ~installation ~sandbox:sandbox.spec () in
    Fs.writeFile ~data path
  in

  return ()
