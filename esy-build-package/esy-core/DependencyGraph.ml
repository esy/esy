
(**
 * Specifies dependency graph kernel.
 *
 * A primitive set of operations required for implementing more complex ones on
 * top.
 *)
module type Kernel = sig
  type t

  (**
   * Given a node — extract its id
   *)
  val id : t -> string

  (**
   * Given a node — a list of dependencies, option is just for convenience —
   * such values will be just filtered
   *)
  val dependencies : t -> t option list
end

module type DependencyGraph = sig

  type t


  (**
   * Fold over dependency graph and compute value of type 'a.
   *)

  type 'a folder
    =  allDependencies : (t * 'a) list
    -> dependencies : (t * 'a) list
    -> t
    -> 'a

  val fold : f:'a folder -> t -> 'a

end

module Make (Kernel : Kernel) : DependencyGraph with type t = Kernel.t = struct

  module StringSet = Set.Make(String)

  type t = Kernel.t

  type 'a folder
    =  allDependencies : (t * 'a) list
    -> dependencies : (t * 'a) list
    -> t
    -> 'a

  let fold ~(f: 'a folder) (pkg : 't) =

    let fCache = Memoize.create ~size:200 in
    let f ~allDependencies ~dependencies pkg =
      fCache (Kernel.id pkg) (fun () -> f ~allDependencies ~dependencies pkg)
    in

    let visitCache = Memoize.create ~size:200 in

    let rec visit pkg =

      let visitDep ((seen, allDependencies, dependencies) as acc) = function
        | Some dep ->
          let depAllDependencies, depDependencies, depValue = visitCached dep in
          let f (seen, allDependencies) (dep, depValue) =
            if StringSet.mem (Kernel.id dep) seen then
              (seen, allDependencies)
            else
              let seen  = StringSet.add (Kernel.id dep) seen in
              let allDependencies = (dep, depValue)::allDependencies in
              (seen, allDependencies)
          in
          let (seen, allDependencies) =
            ListLabels.fold_left ~f ~init:(seen, allDependencies) depDependencies
          in
          let (seen, allDependencies) =
            ListLabels.fold_left ~f ~init:(seen, allDependencies) depAllDependencies
          in
          (seen, allDependencies, (dep, depValue)::dependencies)
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
            (Kernel.dependencies pkg)
        in
        ListLabels.rev allDependencies, List.rev dependencies
      in

      allDependencies, dependencies, f ~allDependencies ~dependencies pkg

    and visitCached pkg =
      visitCache (Kernel.id pkg) (fun () -> visit pkg)
    in

    let _, _, (value : 'a) = visitCached pkg in value

end
