module Version = PackageInfo.Version
module Record = Solution.Record
module Dist = FetchStorage.Dist

let recordsOfSolution solution =
  let set =
    let f set record = Record.Set.add record set in
    Solution.fold ~init:Record.Set.empty ~f solution
  in
  let set = Record.Set.remove (Solution.record solution) set in
  Record.Set.elements set

let traverseWithPath ~path ~f ~init solution =
  let open RunAsync.Syntax in
  let solutionRoot = Solution.record solution in
  let rec aux ~path ~v root =
    let record = Solution.record root in
    let%bind v =
      if Record.equal solutionRoot record
      then return v
      else f ~path v record
    in
    let%bind v =
      let f v dep =
        let record = Solution.record dep in
        let path = Path.(path / "node_modules" // v record.Record.name) in
        aux ~path ~v dep
      in
      RunAsync.List.foldLeft ~f ~init:v (Solution.dependencies root)
    in
    return v
  in
  aux ~path ~v:init solution

let check ~cfg:(cfg : Config.t) (solution : Solution.t) =
  let open RunAsync.Syntax in

  let%bind installed =
    let f ~path installed _record =
      if not installed
      then return false
      else Fs.exists path
    in
    traverseWithPath ~path:cfg.basePath ~f ~init:true solution
  in

  return installed

let fetch ~cfg:(cfg : Config.t) (solution : Solution.t) =
  let open RunAsync.Syntax in

  (* Collect packages which from the solution *)
  let nodeModulesPath = Path.(cfg.basePath / "node_modules") in

  let%bind () = Fs.rmPath nodeModulesPath in
  let%bind () = Fs.createDir nodeModulesPath in

  let records = recordsOfSolution solution in

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
    let f map (record, dist) = Record.Map.add record dist map in
    let map = List.fold_left ~f ~init:Record.Map.empty items in
    return map
  in

  let%bind () =
    let report, finish = cfg.Config.createProgressReporter ~name:"installing" () in
    let f ~path () record =
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
    let%bind () = traverseWithPath ~path:cfg.basePath ~init:() ~f solution in
    let%lwt () = finish () in
    return ()
  in

  return ()
