
(**
 * Specifies dependency graph kernel.
 *
 * A primitive set of operations required for implementing more complex ones on
 * top.
 *)
module type Kernel = sig
  type node
  type dependency

  (**
   * Given a node — extract its id
   *)
  val id : node -> string

  (**
   * Given a node — a list of dependencies, option is just for convenience —
   * such values will be just filtered
   *)
  val traverse : node -> (node * dependency) list
end

module type DependencyGraph = sig

  type node
  type dependency

  (**
   * Fold over dependency graph and compute value of type 'a.
   *)

  type 'a folder
    =  allDependencies : (dependency * 'a) list
    -> dependencies : (dependency * 'a) list
    -> node
    -> 'a

  val fold :
    ?traverse:(node -> (node * dependency) list)
    -> f:'a folder
    -> node
    -> 'a

  (**
   * Find a node in a graph which satisfies the predicate.
   *)
  val find :
    ?traverse:(node -> (node * dependency) list)
    -> f:(node -> bool)
    -> node
    -> node option

end

module Make (Kernel : Kernel) : DependencyGraph
  with
    type node = Kernel.node and
    type dependency = Kernel.dependency
  = struct

  module StringSet = Set.Make(String)

  type node = Kernel.node
  type dependency = Kernel.dependency

  type 'a folder
    =  allDependencies : (dependency * 'a) list
    -> dependencies : (dependency * 'a) list
    -> node
    -> 'a

  let fold ?(traverse=Kernel.traverse) ~(f: 'a folder) (node : node) =

    let fCache = Memoize.create ~size:200 in
    let f ~allDependencies ~dependencies node =
      fCache (Kernel.id node) (fun () -> f ~allDependencies ~dependencies node)
    in

    let visitCache = Memoize.create ~size:200 in

    let rec visit node =

      let visitDep (seen, allDependencies, dependencies) (node, dep) =
        let depAllDependencies, depDependencies, depValue = visitCached node in
        let f (seen, allDependencies) (dep, depValue) =
          if StringSet.mem (Kernel.id node) seen then
            (seen, allDependencies)
          else
            let seen  = StringSet.add (Kernel.id node) seen in
            let allDependencies = (dep, depValue)::allDependencies in
            (seen, allDependencies)
        in

        let ctx = seen, allDependencies in
        let ctx = ListLabels.fold_left ~f ~init:ctx depAllDependencies in
        let ctx = ListLabels.fold_left ~f ~init:ctx depDependencies in
        let ctx = f ctx (dep, depValue) in

        let seen, allDependencies = ctx in
        (seen, allDependencies, (dep, depValue)::dependencies)
      in

      let allDependencies, dependencies =
        let _, allDependencies, dependencies =
          let seen = StringSet.empty in
          let allDependencies = [] in
          let dependencies = [] in
          ListLabels.fold_left
            ~f:visitDep
            ~init:(seen, allDependencies, dependencies)
            (traverse node)
        in
        ListLabels.rev allDependencies, ListLabels.rev dependencies
      in

      allDependencies, dependencies, f ~allDependencies ~dependencies node

    and visitCached node =
      visitCache (Kernel.id node) (fun () -> visit node)
    in

    let _, _, (value : 'a) = visitCached node in value

  let find ?(traverse=Kernel.traverse) ~f node =
    let rec find' = function
      | node::dependencies ->
        if f node then
          Some node
        else begin
          (** Deep first search *)
          let nodeDependencies =
            node
            |> traverse
            |> List.map (fun (node, _dep) -> node)
          in
          match find' nodeDependencies with
          | None -> find' dependencies
          | res -> res
        end
      | [] ->
        None
    in find' [node]

end
