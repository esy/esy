
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

  (**
   * Find a node in a graph which satisfies the predicate.
   *)
  val find : f:(t -> bool) -> t -> t option

end

module Make (Kernel : Kernel) : DependencyGraph with type t = Kernel.t = struct

  module StringSet = Set.Make(String)

  type t = Kernel.t

  type 'a folder
    =  allDependencies : (t * 'a) list
    -> dependencies : (t * 'a) list
    -> t
    -> 'a

  let fold ~(f: 'a folder) (node : 't) =

    let fCache = Memoize.create ~size:200 in
    let f ~allDependencies ~dependencies node =
      fCache (Kernel.id node) (fun () -> f ~allDependencies ~dependencies node)
    in

    let visitCache = Memoize.create ~size:200 in

    let rec visit node =

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

          let ctx = seen, allDependencies in
          let ctx = f ctx (dep, depValue) in
          let ctx = ListLabels.fold_left ~f ~init:ctx depDependencies in
          let ctx = ListLabels.fold_left ~f ~init:ctx depAllDependencies in

          let seen, allDependencies = ctx in
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
            (Kernel.dependencies node)
        in
        ListLabels.rev allDependencies, List.rev dependencies
      in

      allDependencies, dependencies, f ~allDependencies ~dependencies node

    and visitCached node =
      visitCache (Kernel.id node) (fun () -> visit node)
    in

    let _, _, (value : 'a) = visitCached node in value

  let find ~f node =
    let rec find' = function
      | None::dependencies ->
        find' dependencies
      | (Some node)::dependencies ->
        if f node then
          Some node
        else begin
          match find' (Kernel.dependencies node) with
          | None -> find' dependencies
          | res -> res
        end
      | [] ->
        None
    in find' [Some node]

end
