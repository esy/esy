module Version = Package.Version
module Record = Solution.Record
module Dist = FetchStorage.Dist

let uniqueRecordsOfSolution (solution : Solution.t) =
  let set =
    let f set record = Record.Set.add record set in
    Solution.fold ~init:Record.Set.empty ~f solution
  in
  let set = Record.Set.remove (Solution.record solution) set in
  Record.Set.elements set

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
      | One of string
      | Many of string StringMap.t

    let of_yojson =
      let open Result.Syntax in
      function
      | `String cmd -> return (One cmd)
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
    bin : (Bin.t option [@default None]);
    scripts : (Scripts.t [@default Scripts.empty]);
  } [@@deriving of_yojson { strict = false }]

  let ofDir path =
    let open RunAsync.Syntax in
    let%bind json = Fs.readJsonFile Path.(path / "package.json") in
    let%bind manifest = RunAsync.ofRun (Json.parseJsonWith of_yojson json) in
    return manifest

  let packageCommands (path : Path.t) manifest =
    let makePathToCmd cmdPath = Path.(path // v cmdPath |> normalize) in
    match manifest.bin with
    | Some (Bin.One cmd) ->
      [manifest.name, makePathToCmd cmd]
    | Some (Bin.Many cmds) ->
      let f name cmd cmds = (name, makePathToCmd cmd)::cmds in
      (StringMap.fold f cmds [])
    | None -> []

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
    record : Record.t;
    isDirectDependencyOfRoot : bool;
  }

  let pp_installation fmt installation =
    Record.pp fmt installation.record

  let optimize (solution : Solution.t) =

    let index =
      let rec build root (deps, index) =
        let rootDeps, index =
          let f _name dep (deps, index) =
            let deps, index = build dep (deps, index) in
            let deps = Record.Set.add dep.Solution.record deps in
            deps, index
          in
          StringMap.fold f root.Solution.dependencies (Record.Set.empty, index)
        in
        let index = Record.Map.add root.Solution.record rootDeps index in
        let deps = Record.Set.union deps rootDeps in
        deps, index
      in
      let _, index = build solution (Record.Set.empty, Record.Map.empty) in
      index
    in

    let canMove dep dest =
      let aux (record : Record.t) =
        match StringMap.find record.name dest with
        | None -> true
        | Some edep ->
          Record.equal record edep.Solution.record
      in
      aux dep.Solution.record && (
        match Record.Map.find_opt dep.Solution.record index with
        | Some deps -> Record.Set.for_all aux deps
        | None -> true
      )
    in

    let move ~dep (orig, dest) =
      let name = dep.Solution.record.name in
      let dest = StringMap.add name dep dest in
      let orig = StringMap.remove name orig in
      orig, dest
    in

    let rec optDependencies name (root : Solution.t) (parentDependencies : Solution.t StringMap.t) =
      let root = optRoot root in

      let dependencies, parentDependencies =
        let f _name dep (dependencies, parentDependencies) =
          if canMove dep parentDependencies
          then move ~dep (dependencies, parentDependencies)
          else dependencies, parentDependencies
        in
        StringMap.fold
          f
          root.Solution.dependencies
          (root.Solution.dependencies, parentDependencies)
      in

      let root = {root with dependencies} in
      let parentDependencies = StringMap.add name root parentDependencies in
      root, parentDependencies

    and optRoot (root : Solution.t) =
      let dependencies =
        let f name dep dependencies =
          let _ ,dependencies = optDependencies name dep dependencies
          in dependencies
        in
        StringMap.fold
          f
          root.dependencies
          root.dependencies
      in
      {root with dependencies}
    in

    optRoot solution

  let%test_module "optimize" = (module struct

    let make name version dependencies =
      let version = Package.Version.Npm (SemverVersion.Version.parseExn version) in
      let record = Record.{
        name; version;
        source = Package.Source.NoSource; opam = None;
      } in
      Solution.make record dependencies


    let%test "optimize1" =
      let s = make "root" "1.0.0" [
        make "a" "1.0.0" [
          make "dep" "1.0.0" [];
        ];
        make "dep" "1.0.0" [];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [];
          make "dep" "1.0.0" [];
        ]
      )

    let%test "optimize2" =
      let s = make "root" "1.0.0" [
        make "dep" "1.0.0" [];
        make "a" "1.0.0" [
          make "dep" "1.0.0" [];
        ];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [];
          make "dep" "1.0.0" [];
        ]
      )

    let%test "optimize3" =
      let s = make "root" "1.0.0" [
        make "a" "1.0.0" [
          make "dep" "1.0.0" [];
        ];
        make "dep" "2.0.0" [];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [
            make "dep" "1.0.0" [];
          ];
          make "dep" "2.0.0" [];
        ]
      )

    let%test "optimize4" =
      let s = make "root" "1.0.0" [
        make "a" "1.0.0" [
          make "dep" "1.0.0" [];
        ];
        make "b" "1.0.0" [
          make "dep" "1.0.0" [];
        ];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [];
          make "b" "1.0.0" [];
          make "dep" "1.0.0" [];
        ]
      )

    let%test "optimize5" =
      let s = make "root" "1.0.0" [
        make "a" "1.0.0" [
          make "dep" "1.0.0" [];
        ];
        make "b" "1.0.0" [
          make "dep" "2.0.0" [];
        ];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [];
          make "b" "1.0.0" [
            make "dep" "2.0.0" [];
          ];
          make "dep" "1.0.0" [];
        ]
      )

    let%test "optimize6" =
      let s = make "root" "1.0.0" [
        make "a" "1.0.0" [
          make "dep" "1.0.0" [];
        ];
        make "b" "1.0.0" [
          make "dep" "2.0.0" [];
        ];
        make "dep" "2.0.0" [];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [
            make "dep" "1.0.0" [];
          ];
          make "b" "1.0.0" [];
          make "dep" "2.0.0" [];
        ]
      )

    let%test "optimize7" =
      let s = make "root" "1.0.0" [
        make "a" "1.0.0" [
          make "dep" "1.0.0" [];
        ];
        make "b" "1.0.0" [
          make "dep" "2.0.0" [];
        ];
        make "dep" "3.0.0" [];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [
            make "dep" "1.0.0" [];
          ];
          make "b" "1.0.0" [
            make "dep" "2.0.0" [];
          ];
          make "dep" "3.0.0" [];
        ]
      )

    let%test "optimize8" =
      let s = make "root" "1.0.0" [
        make "a" "1.0.0" [
          make "dep" "1.0.0" [];
        ];
        make "b" "1.0.0" [
          make "bb" "1.0.0" [
            make "dep" "1.0.0" [];
          ]
        ];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [];
          make "b" "1.0.0" [];
          make "bb" "1.0.0" [];
          make "dep" "1.0.0" [];
        ]
      )

    let%test "optimize9" =
      let s = make "root" "1.0.0" [
        make "a" "1.0.0" [
          make "bb" "1.0.0" [
            make "dep" "1.0.0" [];
          ]
        ];
        make "b" "1.0.0" [
          make "bb" "1.0.0" [
            make "dep" "1.0.0" [];
          ]
        ];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [];
          make "b" "1.0.0" [];
          make "bb" "1.0.0" [];
          make "dep" "1.0.0" [];
        ]
      )

    let%test "optimize10" =
      let s = make "root" "1.0.0" [
        make "a" "1.0.0" [
          make "bb" "2.0.0" [
            make "dep" "1.0.0" [];
          ]
        ];
        make "b" "1.0.0" [
          make "bb" "1.0.0" [
            make "dep" "1.0.0" [];
          ]
        ];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [];
          make "b" "1.0.0" [
            make "bb" "1.0.0" [];
          ];
          make "bb" "2.0.0" [];
          make "dep" "1.0.0" [];
        ]
      )

    let%test "optimize11" =
      let optimize = optimize in
      let s = make "root" "1.0.0" [
        make "a" "1.0.0" [
          make "bb" "1.0.0" [
            make "dep" "1.0.0" [];
          ]
        ];
        make "b" "1.0.0" [
          make "bb" "2.0.0" [
            make "dep" "2.0.0" [];
          ]
        ];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [];
          make "bb" "1.0.0" [];
          make "dep" "1.0.0" [];
          make "b" "1.0.0" [
            make "bb" "2.0.0" [];
            make "dep" "2.0.0" [];
          ];
        ]
      )

    let%test "optimize12" =
      let optimize = optimize in
      let s = make "root" "1.0.0" [
        make "a" "1.0.0" [
          make "aa" "1.0.0" [
            make "dep" "2.0.0" [];
          ];
        ];
        make "dep" "1.0.0" [];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [
            make "aa" "1.0.0" [];
            make "dep" "2.0.0" [];
          ];
          make "dep" "1.0.0" [];
        ]
      )

    let%test "optimize13" =
      let optimize = optimize in
      let s = make "root" "1.0.0" [
        make "a" "1.0.0" [
          make "bb" "1.0.0" [
            make "dep" "1.0.0" [];
          ]
        ];
        make "b" "1.0.0" [
          make "bb" "2.0.0" [
            make "dep" "1.0.0" [];
          ]
        ];
      ] in
      Solution.equal (optimize s) (
        make "root" "1.0.0" [
          make "a" "1.0.0" [];
          make "bb" "1.0.0" [];
          make "dep" "1.0.0" [];
          make "b" "1.0.0" [
            make "bb" "2.0.0" [];
          ];
        ]
      )

  end)

  let ofSolution ~path (solution : Solution.t) =

    let directDependencies =
      solution.dependencies
      |> StringMap.values
      |> List.map ~f:(fun root -> root.Solution.record)
      |> Record.Set.of_list
    in

    let rec layoutRecord ~path layout root =
      let record = Solution.record root in
      let path = Path.(path / "node_modules" // v record.Record.name) in
      let sourcePath =
        match record.Record.source with
        | Package.Source.Archive _
        | Package.Source.Git _
        | Package.Source.Github _
        | Package.Source.LocalPath _
        | Package.Source.NoSource -> path
        | Package.Source.LocalPathLink path -> path
      in
      let isDirectDependencyOfRoot = Record.Set.mem record directDependencies in
      let layout = {path; sourcePath; record; isDirectDependencyOfRoot}::layout in
      layoutDependenciess ~path layout root

    and layoutDependenciess ~path layout root =
      List.fold_left
        ~f:(layoutRecord ~path)
        ~init:layout
        (Solution.dependencies root)
    in

    let layout =
      layoutDependenciess ~path [] (optimize solution)
    in

    (* Sort the layout so we can have a stable order of operations *)
    let layout =
      let cmp a b = Path.compare a.path b.path in
      List.sort ~cmp layout
    in

    (layout : t)
end

let runLifecycleScript ~installation ~name script =
  let%lwt () = Logs_lwt.app
    (fun m ->
      m "%a: running %a lifecycle"
      Layout.pp_installation installation
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
    let script =
      Printf.sprintf
        "cd %s && %s"
        (Filename.quote (Path.toString installation.path))
        script
    in
    (* TODO(windows): use cmd here *)
    let cmd = "/bin/bash", [|"/bin/bash"; "-c"; script|] in
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

let isInstalled ~cfg:(cfg : Config.t) (solution : Solution.t) =
  let open RunAsync.Syntax in
  let layout = Layout.ofSolution ~path:cfg.basePath solution in
  let f installed {Layout.path;_} =
    if not installed
    then return installed
    else Fs.exists path
  in
  RunAsync.List.foldLeft ~f ~init:true layout

let fetch ~cfg:(cfg : Config.t) (solution : Solution.t) =
  let open RunAsync.Syntax in

  (* Collect packages which from the solution *)
  let nodeModulesPath = Path.(cfg.basePath / "node_modules") in

  let%bind () = Fs.rmPath nodeModulesPath in
  let%bind () = Fs.createDir nodeModulesPath in

  let records = uniqueRecordsOfSolution solution in

  (* Fetch all records *)

  let%bind dists =
    let queue = LwtTaskQueue.create ~concurrency:8 () in
    let report, finish = cfg.Config.createProgressReporter ~name:"fetching" () in
    let%bind items =
      let fetch record =
        let%bind dist =
          LwtTaskQueue.submit queue
          (fun () ->
            let%lwt () =
              let status = Format.asprintf "%a" Record.pp record in
              report status
            in
            FetchStorage.fetch ~cfg record)
        in
        return (record, dist)
      in
      records
      |> List.map ~f:fetch
      |> RunAsync.List.joinAll
    in
    let%lwt () = finish () in
    let map =
      let f map (record, dist) = Record.Map.add record dist map in
      List.fold_left ~f ~init:Record.Map.empty items
    in
    return map
  in

  (* Layout all dists into node_modules *)

  let%bind installed =
    let queue = LwtTaskQueue.create ~concurrency:8 () in
    let report, finish = cfg.Config.createProgressReporter ~name:"installing" () in
    let f ({Layout.path; sourcePath;record;_} as installation) =
      match Record.Map.find_opt record dists with
      | Some dist ->
        let%lwt () =
          let status = Format.asprintf "%a" Dist.pp dist in
          report status
        in
        let%bind () =
          LwtTaskQueue.submit
            queue
            (fun () -> FetchStorage.install ~cfg ~path dist)
        in
        let%bind manifest = Manifest.ofDir sourcePath in
        return (installation, manifest)
      | None ->
        let msg =
          Printf.sprintf
            "inconsistent state: no dist were fetched for %s@%s at %s"
            record.Record.name
            (Version.toString record.Record.version)
            (Path.toString path)
        in
        failwith msg
    in
    let layout = Layout.ofSolution ~path:cfg.basePath solution in
    let%bind installed =
      layout
      |> List.map ~f
      |> RunAsync.List.joinAll
    in
    let%lwt () = finish () in
    return installed
  in

  (* run lifecycle scripts *)

  let%bind () =
    let queue = LwtTaskQueue.create ~concurrency:1 () in

    let f (installation, manifest) =
      LwtTaskQueue.submit
        queue
        (runLifecycle ~installation ~manifest)
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
    let binPath = Path.(cfg.basePath / "node_modules" / ".bin") in
    let%bind () = Fs.createDir binPath in

    let installBinWrapper (name, path) =
      let%bind () = Fs.chmod 0o777 path in
      let%bind () = Fs.symlink ~src:path Path.(binPath / name) in
      return ()
    in

    let installBinWrappersForPkg (item, manifest) =
      Manifest.packageCommands item.Layout.path manifest
      |> List.map ~f:installBinWrapper
      |> RunAsync.List.waitAll
    in

    installed
    |> List.filter ~f:(fun (item, _) -> item.Layout.isDirectDependencyOfRoot)
    |> List.map ~f:installBinWrappersForPkg
    |> RunAsync.List.waitAll
  in


  return ()
