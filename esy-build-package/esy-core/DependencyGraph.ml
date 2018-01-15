module StringSet = Set.Make(String)

type ('t, 'a) folder
  =  allDependencies : ('t * 'a) list
  -> dependencies : ('t * 'a) list
  -> 't
  -> 'a

let fold
  ~(dependenciesOf: 't -> 't option list)
  ~(idOf: 't -> 'id)
  ~(f: ('t, 'a) folder)
  (pkg : 't)
  =

  let fCache = Memoize.create ~size:200 in
  let f ~allDependencies ~dependencies pkg =
    fCache (idOf pkg) (fun () -> f ~allDependencies ~dependencies pkg)
  in

  let visitCache = Memoize.create ~size:200 in

  let rec visit pkg =

    let visitDep acc = function
      | Some pkg ->
        let combine (seen, allDependencies, dependencies) (depAllDependencies, _, dep, depValue) =
          let f (seen, allDependencies) (dep, depValue) =
            if StringSet.mem (idOf dep) seen then
              (seen, allDependencies)
            else
              let seen  = StringSet.add (idOf dep) seen in
              let allDependencies = (dep, depValue)::allDependencies in
              (seen, allDependencies)
          in
          let (seen, allDependencies) =
            ListLabels.fold_left ~f ~init:(seen, allDependencies) depAllDependencies
          in
          (seen, allDependencies, (dep, depValue)::dependencies)
        in combine acc (visitCached pkg)
      | None -> acc
    in

    let allDependencies, dependencies =
      let _, allDependencies, dependencies =
        let seen = StringSet.empty in
        let allDependencies = [] in
        let dependencies = [] in
        ListLabels.fold_left
          ~f:visitDep
          ~init:(seen, allDependencies, dependencies)
          (dependenciesOf pkg)
      in
      ListLabels.rev allDependencies, List.rev dependencies
    in

    allDependencies, dependencies, pkg, f ~allDependencies ~dependencies pkg

  and visitCached pkg =
    visitCache (idOf pkg) (fun () -> visit pkg)
  in

  let _, _, _, (value : 'a) = visitCached pkg in value
