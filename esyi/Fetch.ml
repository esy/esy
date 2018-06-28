module Version = PackageInfo.Version
module Record = Solution.Record
module Dist = FetchStorage.Dist

let uniqueRecordsOfSolution (solution : Solution.t) =
  let set =
    let f set record = Record.Set.add record set in
    Solution.fold ~init:Record.Set.empty ~f solution
  in
  let set = Record.Set.remove (Solution.record solution) set in
  Record.Set.elements set

(* This tries to flatten the solution as much as possible. *)
let optimizeForLayout (solution : Solution.t) =

  let swap ~dep (orig, dest) =
    let name = dep.Solution.record.name in
    let dest = StringMap.add name dep dest in
    let orig = StringMap.remove name orig in
    orig, dest
  in

  let rec optDependencies rootname (root : Solution.t) (dependencies : Solution.t StringMap.t) =
    let root = optRoot root in
    let rootDependencies, dependencies =
      let f depname dep (rootDependencies, dependencies) =
        match StringMap.find depname dependencies with
        | None ->
          swap ~dep (rootDependencies, dependencies)
        | Some edep ->
          if Record.equal dep.Solution.record edep.Solution.record
          then swap ~dep (rootDependencies, dependencies)
          else rootDependencies, dependencies
      in
      StringMap.fold f root.Solution.dependencies (root.Solution.dependencies, dependencies)
    in
    let root = {root with dependencies = rootDependencies} in
    let dependencies = StringMap.add rootname root dependencies in
    dependencies

  and optRoot (root : Solution.t) =
    let dependencies =
      StringMap.fold
        optDependencies
        root.dependencies
        root.dependencies
    in
    {root with dependencies}
  in

  optRoot solution

(*
 * This describes the physical layout of a solution on filesystem.
 *
 * TODO: redesign to allow safe parallel operations - no it's a plain list but
 * maybe we need a nested structure so that different installation do not race
 * with each other. Though the current method of installation (tar xzf) doesn't
 * uncover any issues with that yet.
 *)
module Layout = struct

  type t = (Path.t * Solution.Record.t) list

  let ofSolution ~path (solution : Solution.t) =
    let solution = optimizeForLayout solution in

    let rec layoutRecord ~path layout root =
      let record = Solution.record root in
      let path = Path.(path / "node_modules" // v record.Record.name) in
      let layout = (path, record)::layout in
      layoutDependenciess ~path layout root

    and layoutDependenciess ~path layout root =
      List.fold_left
        ~f:(layoutRecord ~path)
        ~init:layout
        (Solution.dependencies root)
    in

    let layout =
      layoutDependenciess ~path [] solution
    in

    (* Sort the layout so we can have a stable order of operations *)
    let layout =
      let cmp (patha, _) (pathb, _) = Path.compare patha pathb in
      List.sort ~cmp layout
    in

    (layout : t)
end

let isInstalled ~cfg:(cfg : Config.t) (solution : Solution.t) =
  let open RunAsync.Syntax in
  let layout = Layout.ofSolution ~path:cfg.basePath solution in
  let f installed (path, _record) =
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

  let%bind fetched =
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

  (* Layout all fetched packages into node_modules *)

  let%bind () =
    let report, finish = cfg.Config.createProgressReporter ~name:"installing" () in
    let f (path, record) =
      match Record.Map.find_opt record fetched with
      | Some dist ->
        let%lwt () =
          let status = Format.asprintf "%a" Dist.pp dist in
          report status
        in
        FetchStorage.install ~cfg ~path dist
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
    let%bind () =
      layout
      |> List.map ~f
      |> RunAsync.List.waitAll
    in
    let%lwt () = finish () in
    return ()
  in

  return ()
