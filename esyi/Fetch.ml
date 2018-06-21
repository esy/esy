module Version = PackageInfo.Version
module Record = Solution.Record

type layout = (Path.t * Record.t) list

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

let checkSolutionInstalled ~cfg:(cfg : Config.t) (solution : Solution.t) =
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

let fetch ~cfg:(cfg : Config.t)  (solution : Solution.t) =
  let open RunAsync.Syntax in

  (* Collect packages which from the solution *)
  let nodeModulesPath = Path.(cfg.basePath / "node_modules") in

  let%bind () = Fs.rmPath nodeModulesPath in
  let%bind () = Fs.createDir nodeModulesPath in

  let%lwt () =
    Logs_lwt.app (fun m -> m "Checking if there are some packages to fetch...")
  in

  let records = recordsOfSolution solution in

  let%bind fetched =
    let queue = LwtTaskQueue.create ~concurrency:8 () in
    let%bind items =
      let fetch record =
        let%bind dist =
          LwtTaskQueue.submit queue
          (fun () -> FetchStorage.fetch ~cfg record)
        in
        return (record, dist)
      in
      records
      |> List.map ~f:fetch
      |> RunAsync.List.joinAll
    in
    let f map (record, dist) = Record.Map.add record dist map in
    let map = List.fold_left ~f ~init:Record.Map.empty items in
    return map
  in

  let%lwt () = Logs_lwt.app (fun m -> m "Populating node_modules...") in

  let%bind () =
    let f ~path () record =
      match Record.Map.find_opt record fetched with
      | Some dist ->
        let%lwt () = Logs_lwt.app (fun m ->
          let path =
            match Path.relativize ~root:cfg.basePath path with
            | Some path -> path
            | None -> path
          in
          m "Installing %a at %a" Record.pp record Path.pp path)
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
    traverseWithPath ~path:cfg.basePath ~init:() ~f solution
  in

  return ()
