module Queue = struct
  type 'a t = ('a list * 'a list)

  let empty =
    ([], [])

  let is_empty = function
    | [], [] -> true
    | _, _ -> false

  let enqueue el = function
    | [], next -> [el], next
    | cur, next -> cur, el::next

  let rec dequeue = function
    | el::cur, next -> (Some el, (cur, next))
    | [], [] -> (None, empty)
    | [], next -> dequeue (List.rev next, [])
end

module TaskQueue : sig

  type 'a t

  val create : concurrency:int -> unit -> 'a t
  val submit : 'a t -> (unit -> 'a Lwt.t) -> 'a Lwt.t

end = struct

  type 'a t = {
    mutable queue : ('a scheduled * 'a computation) Queue.t;
    mutable running : int;
    concurrency : int;
  }

  and 'a computation = unit -> 'a Lwt.t
  and 'a scheduled = 'a Lwt_condition.t

  let create ~concurrency () = {
    queue = Queue.empty;
    running = 0;
    concurrency
  }

  let submit q f =
    let v = Lwt_condition.create () in

    let rec run (v, f) () =
      try%lwt
        let%lwt r = f () in
        q.running <- q.running - 1;
        Lwt.async next;
        Lwt.return (Lwt_condition.broadcast v r)
      with exn ->
        q.running <- q.running - 1;
        Lwt.async next;
        Lwt.return (Lwt_condition.broadcast_exn v exn)

    and next () =
      match Queue.dequeue q.queue with
      | Some task, queue ->
        q.queue <- queue;
        q.running <- q.running + 1;
        run task ()
      | None, _ -> Lwt.return ()
    in
    if q.running < q.concurrency then (
      q.running <- q.running + 1;
      Lwt.async (run (v, f))
    ) else
      q.queue <- Queue.enqueue (v, f) q.queue;
    Lwt_condition.wait v

end

let waitForDependencies dependencies =
  dependencies
  |> List.map (fun (_, dep) -> dep)
  |> RunAsync.waitAll

let runTask
  ?(force=`ForRoot)
  ?(buildOnly=`ForRoot)
  ~queue
  ~allDependencies:_
  ~dependencies
  (cfg : Config.t)
  (rootTask : BuildTask.t)
  (task : BuildTask.t) =

  let open RunAsync.Syntax in

  let%bind () = waitForDependencies dependencies in

  let isRoot = task.id == rootTask.id in
  let installPath = Config.ConfigPath.toPath cfg task.installPath in

  let buildOnly = match buildOnly with
  | `ForRoot -> isRoot
  | `No -> false
  | `Yes -> true
  in

  let performBuild ?force () =
    let f () =
      let context = Printf.sprintf "building %s@%s" task.pkg.name task.pkg.version in
      let%lwt () = Logs_lwt.app(fun m -> m "%s: starting" context) in
      let%bind () = RunAsync.withContext context (
        PackageBuilder.build ?force ~buildOnly cfg task
      ) in
      let%lwt () = Logs_lwt.app(fun m -> m "%s: complete" context) in
      return ()
    in TaskQueue.submit queue f
  in

  let performBuildIfNeeded () =
    match task.pkg.sourceType with
    | Package.SourceType.Immutable ->
      if%bind Fs.exists installPath
      then return ()
      else performBuild ()
    | Package.SourceType.Development
    | Package.SourceType.Root ->
      performBuild ()
  in

  match force with
  | `ForRoot ->
    if isRoot
    then performBuild ~force:true ()
    else performBuildIfNeeded ()
  | `No ->
    performBuildIfNeeded ()
  | `Yes ->
    performBuild ~force:true ()

(**
 * Build task tree.
 *)
let build
    ?force
    ?buildOnly
    ~concurrency
    (cfg : Config.t)
    (rootTask : BuildTask.t)
    =
  let queue = TaskQueue.create ~concurrency () in
  let f = runTask ?force ?buildOnly ~queue cfg rootTask in
  BuildTask.DependencyGraph.foldWithAllDependencies ~f rootTask

(**
 * Build only dependencies of the task but not the task itself.
 *)
let buildDependencies
    ?force
    ?buildOnly
    ~concurrency
    (cfg : Config.t)
    (rootTask : BuildTask.t)
    =
  let open RunAsync.Syntax in
  let queue = TaskQueue.create ~concurrency () in
  let f ~allDependencies ~dependencies (task : BuildTask.t) =
    if task.id = rootTask.id
    then (
      let%bind () = waitForDependencies dependencies in
      return ()
    ) else runTask ?force ?buildOnly ~allDependencies ~dependencies ~queue cfg rootTask task
  in
  BuildTask.DependencyGraph.foldWithAllDependencies ~f rootTask
