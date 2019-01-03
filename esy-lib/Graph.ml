module type GRAPH = sig
  type t
  type node
  type id
  type traverse = node -> id list

  val empty : id -> t
  val add : t -> node -> t
  val nodes : t -> node list

  val mem : t -> id -> bool
  val isRoot : t -> node -> bool

  val root : t -> node
  val get : t -> id -> node option
  val getExn : t -> id -> node
  val findBy : t -> (id -> node -> bool) -> (id * node) option
  val dependencies : ?traverse:traverse -> t -> node -> node list
  val allDependenciesBFS :
    ?traverse:traverse
    -> ?dependencies:id list
    -> t
    -> id
    -> (bool * node) list

  val fold : f:(node -> node list -> 'v -> 'v) -> init:'v -> t -> 'v
end

module type GRAPH_NODE = sig
  type t

  module Id : sig
    type t

    include S.COMPARABLE with type t := t

    module Map : sig
      include Map.S with type key := t
    end

    module Set : sig
      include Set.S with type elt := t
    end

  end

  val id : t -> Id.t
  val traverse : t -> Id.t list

  include S.COMPARABLE with type t := t
end

module Make (Node : GRAPH_NODE) : GRAPH
  with
    type node = Node.t
    and type id = Node.Id.t
  = struct

  type node = Node.t
  type id = Node.Id.t
  type traverse = node -> id list

  type t = {
    root : Node.Id.t;
    nodes : Node.t Node.Id.Map.t;
  }

  let empty root = {nodes = Node.Id.Map.empty; root}

  let add graph node =
    let nodes = Node.Id.Map.add (Node.id node) node graph.nodes in
    {graph with nodes;}

  let get graph id =
    Node.Id.Map.find_opt id graph.nodes

  let getExn graph id =
    Node.Id.Map.find id graph.nodes

  let root graph =
    getExn graph graph.root 

  let isRoot graph node =
    Node.Id.compare (Node.id node) graph.root = 0

  let mem graph id = Node.Id.Map.mem id graph.nodes

  let nodes graph =
    let f (_, node) = node in
    List.map ~f (Node.Id.Map.bindings graph.nodes)

  let dependencies ?(traverse=Node.traverse) graph node =
    let dependencies = traverse node in
    let f id = getExn graph id in
    List.map ~f dependencies

  let allDependenciesBFS ?(traverse=Node.traverse) ?dependencies graph id =

    let queue  = Queue.create () in
    let enqueue direct dependencies =
      let f id = Queue.add (direct, id) queue in
      List.iter ~f dependencies;
    in

    let rec process (seen, dependencies) =
      match Queue.pop queue with
      | exception Queue.Empty -> seen, dependencies
      | direct, id ->
        if Node.Id.Set.mem id seen
        then process (seen, dependencies)
        else
          let node = Node.Id.Map.find id graph.nodes in
          let seen = Node.Id.Set.add id seen in
          let dependencies = (direct, node)::dependencies in
          enqueue false (traverse node);
          process (seen, dependencies)
    in

    let _, dependencies =
      let dependencies =
        match dependencies with
        | None ->
          let node = Node.Id.Map.find id graph.nodes in
          Node.traverse node
        | Some dependencies -> dependencies
      in
      enqueue true dependencies;
      process (Node.Id.Set.empty, [])
    in

    List.rev dependencies

  let findBy graph f =
    let f (id, node) = f id node in
    let bindings = Node.Id.Map.bindings graph.nodes in
    List.find_opt ~f bindings

  let fold ~f ~init graph =
    let f _id node v =
      let dependencies =
        let f id =
          Node.Id.Map.find id graph.nodes
        in
        List.map ~f (Node.traverse node)
      in
      f node dependencies v
    in
    Node.Id.Map.fold f graph.nodes init

end
