module StringSet = Set.Make(String)

let waitForDependencies dependencies =
  dependencies
  |> List.map ~f:(fun (_, dep) -> dep)
  |> RunAsync.List.waitAll

let buildTask ?(quiet=false) ?force ?stderrout ~buildOnly sandbox (task : Task.t) =
  let pkg = Task.pkg task in
  let f () =
    let open RunAsync.Syntax in
    let context = Printf.sprintf "Building %s@%s" pkg.name pkg.version in
    let%lwt () = if not quiet
      then Logs_lwt.app(fun m -> m "%s: starting" context)
      else Lwt.return ()
    in
    let%bind () =
      RunAsync.context (
        PackageBuilder.build ~quiet ?stderrout ?force ~buildOnly sandbox task
      ) context
    in
    let%lwt () = if not quiet
      then Logs_lwt.app(fun m -> m "%s: complete" context)
      else Lwt.return ()
    in
    return ()
  in
  let label = Printf.sprintf "building %s" pkg.id in
  Perf.measureLwt ~label f

let runTask
  ?(force=`ForRoot)
  ?(buildOnly=`ForRoot)
  ~queue
  ~allDependencies:_
  ~dependencies
  (sandbox : Sandbox.t)
  (rootTask : Task.t)
  (task : Task.t) =

  let open RunAsync.Syntax in

  let%bind () = waitForDependencies dependencies in

  let isRoot = Task.id task == Task.id rootTask in
  let installPath = Sandbox.Path.toPath sandbox.buildConfig (Task.installPath task) in

  let buildOnly = match buildOnly with
  | `ForRoot -> isRoot
  | `No -> false
  | `Yes -> true
  in

  let checkSourceModTime () =
    let f () =
      let infoPath =
        Task.buildInfoPath task
        |> Sandbox.Path.toPath sandbox.buildConfig
      and sourcePath =
        Task.sourcePath task
        |> Sandbox.Path.toPath sandbox.buildConfig
      in
      match%lwt Fs.readFile infoPath with
      | Ok data ->
        let%bind buildInfo = RunAsync.ofRun (
          Json.parseStringWith EsyBuildPackage.BuildInfo.of_yojson data
        ) in
        begin match buildInfo.EsyBuildPackage.BuildInfo.sourceModTime with
        | None -> buildTask ~buildOnly sandbox task
        | Some buildMtime ->
          let skipTraverse path = match Path.basename path with
          | "node_modules"
          | "_esy"
          | "_release"
          | "_build"
          | "_install" -> true
          | _ -> false
          in
          let f mtime _path stat =
            return (
              if stat.Unix.st_mtime > mtime
              then stat.Unix.st_mtime
              else mtime
            )
          in
          let%bind curMtime = Fs.fold ~skipTraverse ~f ~init:0.0 sourcePath in
          if curMtime > buildMtime
          then buildTask ~buildOnly sandbox task
          else return ()
        end
      | Error _ -> buildTask ~buildOnly sandbox task
    in
    let label = Printf.sprintf "checking mtime for %s" (Task.id task) in
    Perf.measureLwt ~label f
  in

  let performBuildIfNeeded () =
    let f () =
    match Task.sourceType task with
    | Manifest.SourceType.Immutable ->
      if%bind Fs.exists installPath
      then return ()
      else buildTask ~buildOnly sandbox task
    | Manifest.SourceType.Transient ->
      if Task.isRoot ~sandbox task then
        buildTask ~buildOnly sandbox task
      else (
        if%bind Fs.exists installPath
        then checkSourceModTime ()
        else buildTask ~buildOnly sandbox task
      )
    in LwtTaskQueue.submit queue f
  in

  match force with
  | `ForRoot ->
    if isRoot
    then buildTask ~force:true ~buildOnly sandbox task
    else performBuildIfNeeded ()
  | `No ->
    performBuildIfNeeded ()
  | `Yes ->
    buildTask ~force:true ~buildOnly sandbox task
  | `Select items ->
    if StringSet.mem (Task.id task) items
    then buildTask ~force:true ~buildOnly sandbox task
    else performBuildIfNeeded ()

(**
 * Build task tree.
 *)
let buildAll
    ?force
    ?buildOnly
    ~concurrency
    (sandbox : Sandbox.t)
    (rootTask : Task.t)
    =
  let queue = LwtTaskQueue.create ~concurrency () in
  let f = runTask ?force ?buildOnly ~queue sandbox rootTask in
  Task.Graph.foldWithAllDependencies ~f rootTask

(**
 * Build only dependencies of the task but not the task itself.
 *)
let buildDependencies
    ?force
    ?buildOnly
    ~concurrency
    (sandbox : Sandbox.t)
    (rootTask : Task.t)
    =
  let open RunAsync.Syntax in
  let queue = LwtTaskQueue.create ~concurrency () in
  let f ~allDependencies ~dependencies (task : Task.t) =
    if Task.id task = Task.id rootTask
    then (
      let%bind () = waitForDependencies dependencies in
      return ()
    )
    else runTask ?force ?buildOnly ~allDependencies ~dependencies ~queue sandbox rootTask task
  in
  Task.Graph.foldWithAllDependencies ~f rootTask
