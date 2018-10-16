module Record = Solution.Record
module Dist = FetchStorage.Dist
module System = EsyLib.System
module Manifest =
  struct
    module Scripts =
      struct
        type t =
          {
          postinstall: ((string option)[@default None]) ;
          install: ((string option)[@default None]) }[@@deriving
                                                       of_yojson
                                                         { strict = false }]
        let empty = { postinstall = None; install = None }
      end
    module Bin =
      struct
        type t =
          | Empty 
          | One of string 
          | Many of string StringMap.t 
        let of_yojson =
          let open Result.Syntax in
            function
            | `String cmd ->
                let cmd = String.trim cmd in
                (match cmd with
                 | "" -> return Empty
                 | cmd -> return (One cmd))
            | `Assoc items ->
                [%bind
                  let items =
                    let f cmds (name, json) =
                      match json with
                      | `String cmd -> return (StringMap.add name cmd cmds)
                      | _ -> error "expected a string" in
                    Result.List.foldLeft ~f ~init:StringMap.empty items in
                  return (Many items)]
            | _ -> error "expected a string or an object"
      end
    type t =
      {
      name: string ;
      bin: ((Bin.t)[@default Bin.Empty]) ;
      scripts: ((Scripts.t)[@default Scripts.empty]) ;
      esy: ((Json.t option)[@default None]) }[@@deriving
                                               of_yojson { strict = false }]
    let ofDir path =
      let open RunAsync.Syntax in
        let filename = let open Path in path / "package.json" in
        [%bind
          if Fs.exists filename
          then
            [%bind
              let json = Fs.readJsonFile filename in
              [%bind
                let manifest =
                  RunAsync.ofRun (Json.parseJsonWith of_yojson json) in
                return (Some manifest)]]
          else return None]
    let packageCommands (sourcePath : Path.t) manifest =
      let makePathToCmd cmdPath =
        let open Path in (sourcePath // (v cmdPath)) |> normalize in
      match manifest.bin with
      | Bin.One cmd -> [((manifest.name), (makePathToCmd cmd))]
      | Bin.Many cmds ->
          let f name cmd cmds = (name, (makePathToCmd cmd)) :: cmds in
          StringMap.fold f cmds []
      | Bin.Empty -> []
  end
module Layout =
  struct
    type t = installation list
    and installation =
      {
      path: Path.t ;
      sourcePath: Path.t ;
      record: Record.t ;
      isDirectDependencyOfRoot: bool }
    let pp_installation fmt installation =
      Fmt.pf fmt "%a at %a" Record.pp installation.record Path.pp
        installation.path
    let pp = let open Fmt in list ~sep:(unit "@\n") pp_installation
    let ofSolution ~nodeModulesPath  sandboxPath (sol : Solution.t) =
      match Solution.root sol with
      | None -> []
      | Some root ->
          let isDirectDependencyOfRoot =
            let directDependencies = Solution.dependencies root sol in
            fun record -> Record.Set.mem record directDependencies in
          let markAsOccupied insertion breadcrumb record =
            let (_, insertionPath) = insertion in
            let rec aux =
              function
              | (modules, path)::rest ->
                  (Hashtbl.replace modules record.Record.name record;
                   if (Path.compare insertionPath path) = 0
                   then ()
                   else aux rest)
              | [] -> () in
            aux breadcrumb in
          let rec findInsertion record breacrumb =
            match breacrumb with
            | [] -> `None
            | ((modules, _) as here)::upTheTree ->
                (match Hashtbl.find_opt modules record.Record.name with
                 | Some r ->
                     if (Record.compare r record) = 0
                     then `Done (here, (here :: upTheTree))
                     else `None
                 | None ->
                     (match findInsertion record upTheTree with
                      | `Ok nextItem -> `Ok nextItem
                      | `Done there -> `Done there
                      | `None -> `Ok (here, (here :: upTheTree)))) in
          let layoutRecord ~this  ~breadcrumb  ~layout  record =
            let insert ((_modules, path) as here) =
              markAsOccupied here (this :: breadcrumb) record;
              (let path = let open Path in path // (v record.Record.name) in
               let sourcePath =
                 let (main, _) = record.Record.source in
                 match main with
                 | Source.Archive _|Source.Git _|Source.Github _
                   |Source.LocalPath _|Source.NoSource -> path
                 | Source.LocalPathLink { path; manifest = _ } ->
                     let open Path in sandboxPath // path in
               let installation =
                 {
                   path;
                   sourcePath;
                   record;
                   isDirectDependencyOfRoot =
                     (isDirectDependencyOfRoot record)
                 } in
               installation :: layout) in
            match findInsertion record breadcrumb with
            | `Done (there, _) ->
                (markAsOccupied there (this :: breadcrumb) record; None)
            | `Ok (here, breadcrumb) -> Some ((insert here), breadcrumb)
            | `None -> Some ((insert this), (this :: breadcrumb)) in
          let rec layoutDependencies ~seen  ~breadcrumb  ~layout  record =
            let this =
              let modules = Hashtbl.create 100 in
              let path =
                match breadcrumb with
                | (_modules, path)::_ ->
                    let open Path in
                      (path // (v record.Record.name)) / "node_modules"
                | [] -> nodeModulesPath in
              (modules, path) in
            let dependencies = Solution.dependencies record sol in
            let (layout, dependenciesWithBreadcrumbs) =
              let f r (layout, dependenciesWithBreadcrumbs) =
                match layoutRecord ~this ~breadcrumb ~layout r with
                | Some (layout, breadcrumb) ->
                    (layout, ((r, breadcrumb) ::
                      dependenciesWithBreadcrumbs))
                | None -> (layout, dependenciesWithBreadcrumbs) in
              Record.Set.fold f dependencies (layout, []) in
            let layout =
              let seen = Record.Set.add record seen in
              let f layout (r, breadcrumb) =
                match Record.Set.mem r seen with
                | true -> layout
                | false -> layoutDependencies ~seen ~breadcrumb ~layout r in
              List.fold_left ~f ~init:layout dependenciesWithBreadcrumbs in
            layout in
          let layout =
            layoutDependencies ~seen:Record.Set.empty ~breadcrumb:[]
              ~layout:[] root in
          let layout =
            let cmp a b = Path.compare a.path b.path in List.sort ~cmp layout in
          (layout : t)
    [%%test_module
      let "Layout" = (module
        struct
          let parseVersionExn v =
            match SemverVersion.Version.parse v with
            | Ok v -> v
            | Error msg -> failwith msg
          let r name version =
            ({
               Record.name = name;
               version = (Version.Npm (parseVersionExn version));
               source = (Source.NoSource, []);
               overrides = Package.Overrides.empty;
               files = [];
               opam = None
             } : Record.t)
          let id name version =
            let version = version ^ ".0.0" in
            let version = Version.Npm (parseVersionExn version) in
            ((name, version) : Solution.Id.t)
          let expect layout expectation =
            let convert =
              let f (installation : installation) =
                ((Format.asprintf "%a" Record.pp installation.record),
                  (Path.show installation.path)) in
              List.map ~f layout in
            if (Pervasives.compare convert expectation) = 0
            then true
            else (Format.printf "Got:@[<v 2>@\n%a@]@\n" pp layout; false)
          [%%test
            let "simple" =
              let sol =
                let open Solution in
                  ((empty |> (add ~record:(r "a" "1") ~dependencies:[])) |>
                     (add ~record:(r "b" "1") ~dependencies:[]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("b@1.0.0", "./node_modules/b")]]
          [%%test
            let "simple2" =
              let sol =
                let open Solution in
                  ((empty |> (add ~record:(r "a" "1") ~dependencies:[])) |>
                     (add ~record:(r "b" "1") ~dependencies:[id "a" "1"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("b@1.0.0", "./node_modules/b")]]
          [%%test
            let "simple3" =
              let sol =
                let open Solution in
                  (((empty |> (add ~record:(r "c" "1") ~dependencies:[])) |>
                      (add ~record:(r "a" "1") ~dependencies:[id "c" "1"]))
                     |> (add ~record:(r "b" "1") ~dependencies:[id "c" "1"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("b@1.0.0", "./node_modules/b");
                ("c@1.0.0", "./node_modules/c")]]
          [%%test
            let "conflict" =
              let sol =
                let open Solution in
                  (((empty |> (add ~record:(r "a" "1") ~dependencies:[])) |>
                      (add ~record:(r "a" "2") ~dependencies:[]))
                     |> (add ~record:(r "b" "1") ~dependencies:[id "a" "2"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("b@1.0.0", "./node_modules/b");
                ("a@2.0.0", "./node_modules/b/node_modules/a")]]
          [%%test
            let "conflict2" =
              let sol =
                let open Solution in
                  ((((empty |>
                        (add ~record:(r "shared" "1") ~dependencies:[]))
                       |>
                       (add ~record:(r "a" "1")
                          ~dependencies:[id "shared" "1"]))
                      |>
                      (add ~record:(r "a" "2")
                         ~dependencies:[id "shared" "1"]))
                     |> (add ~record:(r "b" "1") ~dependencies:[id "a" "2"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("b@1.0.0", "./node_modules/b");
                ("a@2.0.0", "./node_modules/b/node_modules/a");
                ("shared@1.0.0", "./node_modules/shared")]]
          [%%test
            let "conflict3" =
              let sol =
                let open Solution in
                  (((((empty |>
                         (add ~record:(r "shared" "1") ~dependencies:[]))
                        |> (add ~record:(r "shared" "2") ~dependencies:[]))
                       |>
                       (add ~record:(r "a" "1")
                          ~dependencies:[id "shared" "1"]))
                      |>
                      (add ~record:(r "a" "2")
                         ~dependencies:[id "shared" "2"]))
                     |> (add ~record:(r "b" "1") ~dependencies:[id "a" "2"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("shared@1.0.0", "./node_modules/a/node_modules/shared");
                ("b@1.0.0", "./node_modules/b");
                ("a@2.0.0", "./node_modules/b/node_modules/a");
                ("shared@2.0.0", "./node_modules/shared")]]
          [%%test
            let "conflict4" =
              let sol =
                let open Solution in
                  ((((empty |> (add ~record:(r "c" "1") ~dependencies:[])) |>
                       (add ~record:(r "c" "2") ~dependencies:[]))
                      |> (add ~record:(r "a" "1") ~dependencies:[id "c" "1"]))
                     |> (add ~record:(r "b" "1") ~dependencies:[id "c" "2"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("c@1.0.0", "./node_modules/a/node_modules/c");
                ("b@1.0.0", "./node_modules/b");
                ("c@2.0.0", "./node_modules/c")]]
          [%%test
            let "nested" =
              let sol =
                let open Solution in
                  ((((empty |> (add ~record:(r "d" "1") ~dependencies:[])) |>
                       (add ~record:(r "c" "1") ~dependencies:[id "d" "1"]))
                      |> (add ~record:(r "a" "1") ~dependencies:[id "c" "1"]))
                     |> (add ~record:(r "b" "1") ~dependencies:[id "c" "1"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("b@1.0.0", "./node_modules/b");
                ("c@1.0.0", "./node_modules/c");
                ("d@1.0.0", "./node_modules/d")]]
          [%%test
            let "nested conflict" =
              let sol =
                let open Solution in
                  (((((empty |> (add ~record:(r "d" "1") ~dependencies:[]))
                        |>
                        (add ~record:(r "c" "1") ~dependencies:[id "d" "1"]))
                       |>
                       (add ~record:(r "c" "2") ~dependencies:[id "d" "1"]))
                      |> (add ~record:(r "a" "1") ~dependencies:[id "c" "1"]))
                     |> (add ~record:(r "b" "1") ~dependencies:[id "c" "2"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("c@1.0.0", "./node_modules/a/node_modules/c");
                ("b@1.0.0", "./node_modules/b");
                ("c@2.0.0", "./node_modules/c");
                ("d@1.0.0", "./node_modules/d")]]
          [%%test
            let "nested conflict 2" =
              let sol =
                let open Solution in
                  ((((((empty |> (add ~record:(r "d" "1") ~dependencies:[]))
                         |> (add ~record:(r "d" "2") ~dependencies:[]))
                        |>
                        (add ~record:(r "c" "1") ~dependencies:[id "d" "1"]))
                       |>
                       (add ~record:(r "c" "2") ~dependencies:[id "d" "2"]))
                      |> (add ~record:(r "a" "1") ~dependencies:[id "c" "1"]))
                     |> (add ~record:(r "b" "1") ~dependencies:[id "c" "2"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("c@1.0.0", "./node_modules/a/node_modules/c");
                ("d@1.0.0", "./node_modules/a/node_modules/d");
                ("b@1.0.0", "./node_modules/b");
                ("c@2.0.0", "./node_modules/c");
                ("d@2.0.0", "./node_modules/d")]]
          [%%test
            let "nested conflict 3" =
              let sol =
                let open Solution in
                  ((((empty |> (add ~record:(r "d" "1") ~dependencies:[])) |>
                       (add ~record:(r "d" "2") ~dependencies:[]))
                      |> (add ~record:(r "b" "1") ~dependencies:[id "d" "1"]))
                     |> (add ~record:(r "a" "1") ~dependencies:[id "b" "1"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "d" "2"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("b@1.0.0", "./node_modules/b");
                ("d@1.0.0", "./node_modules/b/node_modules/d");
                ("d@2.0.0", "./node_modules/d")]]
          [%%test
            let "nested conflict 4" =
              let sol =
                let open Solution in
                  (((((empty |> (add ~record:(r "d" "1") ~dependencies:[]))
                        |>
                        (add ~record:(r "c" "1") ~dependencies:[id "d" "1"]))
                       |>
                       (add ~record:(r "c" "2") ~dependencies:[id "d" "1"]))
                      |> (add ~record:(r "b" "1") ~dependencies:[id "c" "2"]))
                     |> (add ~record:(r "a" "1") ~dependencies:[id "c" "1"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("c@1.0.0", "./node_modules/a/node_modules/c");
                ("b@1.0.0", "./node_modules/b");
                ("c@2.0.0", "./node_modules/c");
                ("d@1.0.0", "./node_modules/d")]]
          [%%test
            let "nested conflict 5" =
              let sol =
                let open Solution in
                  ((((((empty |> (add ~record:(r "d" "1") ~dependencies:[]))
                         |> (add ~record:(r "d" "2") ~dependencies:[]))
                        |>
                        (add ~record:(r "c" "1") ~dependencies:[id "d" "1"]))
                       |>
                       (add ~record:(r "c" "2") ~dependencies:[id "d" "2"]))
                      |> (add ~record:(r "b" "1") ~dependencies:[id "c" "2"]))
                     |> (add ~record:(r "a" "1") ~dependencies:[id "c" "1"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("c@1.0.0", "./node_modules/a/node_modules/c");
                ("d@1.0.0", "./node_modules/a/node_modules/d");
                ("b@1.0.0", "./node_modules/b");
                ("c@2.0.0", "./node_modules/c");
                ("d@2.0.0", "./node_modules/d")]]
          [%%test
            let "nested conflict 6" =
              let sol =
                let open Solution in
                  ((((empty |>
                        (add ~record:(r "punycode" "1") ~dependencies:[]))
                       |> (add ~record:(r "punycode" "2") ~dependencies:[]))
                      |>
                      (add ~record:(r "url" "1")
                         ~dependencies:[id "punycode" "2"]))
                     |>
                     (add ~record:(r "browserify" "1")
                        ~dependencies:[id "punycode" "1"; id "url" "1"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "browserify" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("browserify@1.0.0", "./node_modules/browserify");
                ("punycode@1.0.0", "./node_modules/punycode");
                ("url@1.0.0", "./node_modules/url");
                ("punycode@2.0.0",
                  "./node_modules/url/node_modules/punycode")]]
          [%%test
            let "loop 1" =
              let sol =
                let open Solution in
                  ((empty |>
                      (add ~record:(r "b" "1") ~dependencies:[id "a" "1"]))
                     |> (add ~record:(r "a" "1") ~dependencies:[id "b" "1"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("b@1.0.0", "./node_modules/b")]]
          [%%test
            let "loop 2" =
              let sol =
                let open Solution in
                  (((empty |> (add ~record:(r "c" "1") ~dependencies:[])) |>
                      (add ~record:(r "b" "1")
                         ~dependencies:[id "a" "1"; id "c" "1"]))
                     |> (add ~record:(r "a" "1") ~dependencies:[id "b" "1"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("b@1.0.0", "./node_modules/b");
                ("c@1.0.0", "./node_modules/c")]]
          [%%test
            let "loop 3" =
              let sol =
                let open Solution in
                  (((empty |>
                       (add ~record:(r "c" "1") ~dependencies:[id "a" "1"]))
                      |> (add ~record:(r "b" "1") ~dependencies:[id "a" "1"]))
                     |>
                     (add ~record:(r "a" "1")
                        ~dependencies:[id "b" "1"; id "c" "1"]))
                    |>
                    (addRoot ~record:(r "root" "1")
                       ~dependencies:[id "a" "1"; id "b" "1"]) in
              let layout =
                ofSolution ~nodeModulesPath:(Path.v "./node_modules")
                  (Path.v ".") sol in
              expect layout
                [("a@1.0.0", "./node_modules/a");
                ("b@1.0.0", "./node_modules/b");
                ("c@1.0.0", "./node_modules/c")]]
        end)]
  end
let runLifecycleScript ~installation  ~name  script =
  [%lwt
    let () =
      Logs_lwt.app
        (fun m ->
           m "%a: running %a lifecycle" Record.pp installation.Layout.record
             (let open Fmt in styled `Bold string) name) in
    let readAndCloseChan ic =
      Lwt.finalize (fun () -> Lwt_io.read ic) (fun () -> Lwt_io.close ic) in
    let f p =
      [%lwt
        let stdout = readAndCloseChan p#stdout
        and stderr = readAndCloseChan p#stderr in
        [%lwt
          match p#status with
          | Unix.WEXITED 0 -> RunAsync.return ()
          | _ ->
              [%lwt
                (Logs_lwt.err
                   (fun m ->
                      m
                        "@[<v>command failed: %s@\nstderr:@[<v 2>@\n%s@]@\nstdout:@[<v 2>@\n%s@]@]"
                        script stderr stdout);
                 RunAsync.error "error running command")]]] in
    [%lwt
      try
        let installationPath =
          match System.Platform.host with
          | Windows -> Path.show installation.path
          | _ -> Filename.quote (Path.show installation.path) in
        let script = Printf.sprintf "cd %s && %s" installationPath script in
        let cmd =
          match System.Platform.host with
          | Windows -> ("", [|"cmd.exe";("/c " ^ script)|])
          | _ -> ("/bin/bash", [|"/bin/bash";"-c";script|]) in
        Lwt_process.with_process_full cmd f
      with
      | Unix.Unix_error (err, _, _) ->
          let msg = Unix.error_message err in RunAsync.error msg
      | _ -> RunAsync.error "error running subprocess"]]
let runLifecycle ~installation  ~manifest:(manifest : Manifest.t)  () =
  let open RunAsync.Syntax in
    [%bind
      let () =
        match (manifest.scripts).install with
        | Some cmd -> runLifecycleScript ~installation ~name:"install" cmd
        | None -> return () in
      [%bind
        let () =
          match (manifest.scripts).postinstall with
          | Some cmd ->
              runLifecycleScript ~installation ~name:"postinstall" cmd
          | None -> return () in
        return ()]]
let isInstalled ~sandbox:(sandbox : Sandbox.t)  (solution : Solution.t) =
  let open RunAsync.Syntax in
    let nodeModulesPath = SandboxSpec.nodeModulesPath sandbox.spec in
    let layout =
      Layout.ofSolution ~nodeModulesPath (sandbox.spec).path solution in
    let f installed { Layout.path = path;_} =
      if not installed then return installed else Fs.exists path in
    RunAsync.List.foldLeft ~f ~init:true layout
let fetch ~sandbox:(sandbox : Sandbox.t)  (solution : Solution.t) =
  let open RunAsync.Syntax in
    let nodeModulesPath = SandboxSpec.nodeModulesPath sandbox.spec in
    [%bind
      let () = Fs.rmPath nodeModulesPath in
      [%bind
        let () = Fs.createDir nodeModulesPath in
        let records =
          match Solution.root solution with
          | Some root ->
              let all = Solution.records solution in
              Record.Set.remove root all
          | None -> Solution.records solution in
        [%bind
          let dists =
            let queue = LwtTaskQueue.create ~concurrency:8 () in
            let (report, finish) =
              Cli.createProgressReporter ~name:"fetching" () in
            [%bind
              let items =
                let fetch record =
                  [%bind
                    let dist =
                      LwtTaskQueue.submit queue
                        (fun () ->
                           [%lwt
                             let () =
                               let status =
                                 Format.asprintf "%a" Record.pp record in
                               report status in
                             FetchStorage.fetch ~cfg:(sandbox.cfg) record]) in
                    return (record, dist)] in
                ((records |> Record.Set.elements) |> (List.map ~f:fetch)) |>
                  RunAsync.List.joinAll in
              [%lwt
                let () = finish () in
                let map =
                  let f map (record, dist) = Record.Map.add record dist map in
                  List.fold_left ~f ~init:Record.Map.empty items in
                return map]] in
          [%bind
            let installed =
              let queue = LwtTaskQueue.create ~concurrency:4 () in
              let (report, finish) =
                Cli.createProgressReporter ~name:"installing" () in
              let f
                ({ Layout.path = path; sourcePath; record;_} as installation)
                () =
                match Record.Map.find_opt record dists with
                | Some dist ->
                    [%lwt
                      let () =
                        let status = Format.asprintf "%a" Dist.pp dist in
                        report status in
                      [%bind
                        let () =
                          FetchStorage.install ~cfg:(sandbox.cfg) ~path dist in
                        [%bind
                          let manifest = Manifest.ofDir sourcePath in
                          return (installation, manifest)]]]
                | None ->
                    let msg =
                      Printf.sprintf
                        "inconsistent state: no dist were fetched for %s@%s at %s"
                        record.Record.name
                        (Version.show record.Record.version) (Path.show path) in
                    failwith msg in
              let layout =
                Layout.ofSolution ~nodeModulesPath (sandbox.spec).path
                  solution in
              [%bind
                let installed =
                  let install installation =
                    RunAsync.contextf
                      (LwtTaskQueue.submit queue (f installation))
                      "installing %a" Layout.pp_installation installation in
                  (layout |> (List.map ~f:install)) |> RunAsync.List.joinAll in
                [%lwt let () = finish () in return installed]] in
            [%bind
              let () =
                let queue = LwtTaskQueue.create ~concurrency:1 () in
                let f =
                  function
                  | (installation, Some
                     ({ Manifest.esy = None;_} as manifest)) ->
                      RunAsync.contextf
                        (LwtTaskQueue.submit queue
                           (runLifecycle ~installation ~manifest))
                        "running lifecycle %a" Layout.pp_installation
                        installation
                  | (_installation, Some { Manifest.esy = Some _;_})
                    |(_installation, None) -> return () in
                [%bind
                  let () =
                    (installed |> (List.map ~f)) |> RunAsync.List.waitAll in
                  return ()] in
              [%bind
                let () =
                  let nodeModulesPath =
                    SandboxSpec.nodeModulesPath sandbox.spec in
                  let binPath = let open Path in nodeModulesPath / ".bin" in
                  [%bind
                    let () = Fs.createDir binPath in
                    let installBinWrapper (name, path) =
                      [%bind
                        if Fs.exists path
                        then
                          [%bind
                            let () = Fs.chmod 0o777 path in
                            Fs.symlink ~src:path
                              (let open Path in binPath / name)]
                        else
                          [%lwt
                            (Logs_lwt.warn
                               (fun m ->
                                  m "missing %a defined as binary" Path.pp
                                    path);
                             return ())]] in
                    let installBinWrappersForPkg =
                      function
                      | (installation, Some manifest) ->
                          ((Manifest.packageCommands
                              installation.Layout.sourcePath manifest)
                             |> (List.map ~f:installBinWrapper))
                            |> RunAsync.List.waitAll
                      | (_installation, None) -> return () in
                    ((installed |>
                        (List.filter
                           ~f:(fun (installation, _) ->
                                 installation.Layout.isDirectDependencyOfRoot)))
                       |> (List.map ~f:installBinWrappersForPkg))
                      |> RunAsync.List.waitAll] in
                [%bind
                  let () =
                    if SandboxSpec.isDefault sandbox.spec
                    then
                      let nodeModulesPath =
                        SandboxSpec.nodeModulesPath sandbox.spec in
                      let targetPath =
                        let open Path in (sandbox.spec).path / "node_modules" in
                      [%bind
                        let () = Fs.rmPath targetPath in
                        [%bind
                          let () = Fs.symlink ~src:nodeModulesPath targetPath in
                          return ()]]
                    else return () in
                  [%bind
                    let () =
                      let packagesPath =
                        SandboxSpec.nodeModulesPath sandbox.spec in
                      [%bind
                        let items = Fs.listDir packagesPath in
                        let items = String.concat " " items in
                        let data = "(ignored_subdirs (" ^ (items ^ "))\n") in
                        Fs.writeFile ~data
                          (let open Path in packagesPath / "dune")] in
                    return ()]]]]]]]]