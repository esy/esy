
(**
 * Specifies dependency graph kernel.
 *
 * A primitive set of operations required for implementing more complex ones on
 * top.
 *)
module type Kernel = sig
  type t

  module Dependency : sig
    type t
    val compare : t -> t -> int
  end

  val compare : t -> t -> int

  (**
   * Given a node — extract its id.
   *)
  val id : t -> string

  (**
   * Given a node — get a list of dependencies with corresponding nodes.
   *)
  val traverse : t -> (t * Dependency.t) list
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

  val foldWithAllDependencies :
    ?traverse:(node -> (node * dependency) list)
    -> f:'a folder
    -> node
    -> 'a


  val fold :
    ?traverse:(node -> (node * dependency) list)
    -> init:'a
    -> f:(foldDependencies : (unit -> (dependency * 'a) list) -> 'a -> node -> 'a)
    -> node
    -> 'a

  val traverse :
    ?traverse:(node -> (node * dependency) list)
    -> node
    -> node list

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
    type node = Kernel.t and
    type dependency = Kernel.Dependency.t
  = struct

  module NodeSet = Set.Make(Kernel)
  module DependencySet = Set.Make(Kernel.Dependency)

  type node = Kernel.t
  type dependency = Kernel.Dependency.t

  type 'a folder
    =  allDependencies : (dependency * 'a) list
    -> dependencies : (dependency * 'a) list
    -> node
    -> 'a

  let foldWithAllDependencies ?(traverse=Kernel.traverse) ~(f: 'a folder) (node : node) =

    let fCached =
      Memoize.make
        ~size:200
        ()
    in

    let f ~allDependencies ~dependencies node =
      Memoize.compute
        fCached
        (Kernel.id node)
        (fun () -> f ~allDependencies ~dependencies node)
    in


    let visitCache = Memoize.make ~size:200 () in

    let rec visit node =

      let visitDep (seen, allDependencies, dependencies) (node, dep) =
        let depAllDependencies, depDependencies, depValue = visitCached node in
        let f (seen, allDependencies) (node, dep, depValue) =
          if DependencySet.mem dep seen then
            (seen, allDependencies)
          else
            let seen  = DependencySet.add dep seen in
            let allDependencies = (node, dep, depValue)::allDependencies in
            (seen, allDependencies)
        in

        let ctx = seen, allDependencies in
        let ctx = List.fold_left ~f ~init:ctx depAllDependencies in
        let ctx = List.fold_left ~f ~init:ctx depDependencies in
        let ctx = f ctx (node, dep, depValue) in

        let seen, allDependencies = ctx in
        (seen, allDependencies, (node, dep, depValue)::dependencies)
      in

      let allDependencies, dependencies =
        let _, allDependencies, dependencies =
          let seen = DependencySet.empty in
          let allDependencies = [] in
          let dependencies = [] in
          List.fold_left
            ~f:visitDep
            ~init:(seen, allDependencies, dependencies)
            (traverse node)
        in
        List.rev allDependencies, List.rev dependencies
      in

      let value =
        let skipNode (_node, dep, v) = (dep, v) in
        let allDependencies = List.map ~f:skipNode allDependencies
        and dependencies = List.map ~f:skipNode dependencies in
        f ~allDependencies ~dependencies node
      in
      allDependencies, dependencies, value

    and visitCached node =
      Memoize.compute visitCache (Kernel.id node) (fun () -> visit node)
    in

    let _, _, (value : 'a) = visitCached node in value

  let rec fold ?(traverse=Kernel.traverse) ~(init : 'a) ~f node =
    let foldDependencies () =
      node |> traverse |> List.map ~f:(fun (node, dep) ->
        let v = fold ~traverse ~f ~init node in
        (dep, v))
    in
    f ~foldDependencies init node

  let traverse ?(traverse=Kernel.traverse) node =
    let rec aux (seen, nodes) node =
      if NodeSet.mem node seen then
        (seen, nodes)
      else
        let (seen, nodes) =
          let dependencies =
            node
            |> traverse
            |> List.map ~f:(fun (node, _) -> node)
          in
          List.fold_left
            ~f:aux
            ~init:(seen, nodes)
            dependencies
        in
        (NodeSet.add node seen, node::nodes)
    in
    let _, nodes = aux (NodeSet.empty, []) node in
    nodes

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
            |> List.map ~f:(fun (node, _dep) -> node)
          in
          match find' nodeDependencies with
          | None -> find' dependencies
          | res -> res
        end
      | [] ->
        None
    in find' [node]

end
