module Record = Solution.Record
module RecordSet = Set.Make(struct
  type t = Record.t
  let compare pkga pkgb =
    let c = String.compare pkga.Record.name pkgb.Record.name in
    if c = 0
    then PackageInfo.Version.compare pkga.version pkgb.version
    else c
end)

type layout = (Path.t * Record.t) list

let packagesOfSolution solution =
  let rec addRoot pkgs root =
    pkgs
    |> RecordSet.add root.Solution.root
    |> fun pkgs -> List.fold_left ~f:addRoot ~init:pkgs root.Solution.dependencies
  in
  let pkgs =
    List.fold_left
      ~f:addRoot
      ~init:RecordSet.empty
      solution.Solution.dependencies
  in
  RecordSet.elements pkgs

let layoutOfSolution basePath solution =
  let rec layoutRoot basePath layout root =
     let recordPath = Path.(basePath / "node_modules" // v root.Solution.root.name) in
     let layout = (recordPath, root.Solution.root)::layout in
     List.fold_left
      ~f:(layoutRoot recordPath)
      ~init:layout
      root.Solution.dependencies
  in
  let layout =
    List.fold_left
    ~f:(layoutRoot basePath)
    ~init:[]
    solution.Solution.dependencies
  in
  layout

let checkSolutionInstalled ~cfg:(cfg : Config.t) (solution : Solution.t) =
  let open RunAsync.Syntax in
  let layout = layoutOfSolution cfg.basePath solution in
  let%bind installed =
    layout
    |> List.map ~f:(fun (path, _) -> Fs.exists path)
    |> RunAsync.List.joinAll
  in
  return (List.for_all ~f:(fun installed -> installed) installed)

let fetch ~cfg:(cfg : Config.t)  (solution : Solution.t) =
  let open RunAsync.Syntax in

  (* Collect packages which from the solution *)
  let packagesToFetch = packagesOfSolution solution in
  let nodeModulesPath = Path.(cfg.basePath / "node_modules") in

  let%bind () = Fs.rmPath nodeModulesPath in
  let%bind () = Fs.createDir nodeModulesPath in

  let%lwt () =
    Logs_lwt.app (fun m -> m "Checking if there are some packages to fetch...")
  in

  let%bind packagesFetched =
    let queue = LwtTaskQueue.create ~concurrency:8 () in
    packagesToFetch
    |> List.map ~f:(fun pkg ->
        let%bind fetchedPkg =
          LwtTaskQueue.submit queue
          (fun () -> FetchStorage.fetch ~cfg pkg)
        in return (pkg, fetchedPkg))
    |> RunAsync.List.joinAll
  in

  let%lwt () = Logs_lwt.app (fun m -> m "Populating node_modules...") in

  let packageInstallPath =
    let layout = layoutOfSolution cfg.basePath solution in
    fun pkg ->
      let (path, _) =
        List.find
          ~f:(fun (_path, p) ->
            String.equal p.Record.name pkg.Record.name
            && PackageInfo.Version.equal p.Record.version pkg.Record.version)
          layout
      in path
  in

  let%bind () =
    RunAsync.List.processSeq
      ~f:(fun (pkg, fetchedPkg) ->
        let dst = packageInstallPath pkg in
        FetchStorage.install ~cfg ~dst fetchedPkg)
    packagesFetched
  in

  return ()
