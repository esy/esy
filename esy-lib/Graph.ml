module type GRAPH = sig
  type t
  type node
  type id

  val empty : id -> t
  val add : node -> id list -> t -> t

  val root : t -> node
  val mem : id -> t -> bool
  val find : id -> t -> node option
  val findExn : id -> t -> node
  val dependencies : node -> t -> node list
  val allDependencies : node -> t -> node list

  val fold : f:(node -> node list -> 'v -> 'v) -> init:'v -> t -> 'v

  include S.JSONABLE with type t := t
end

module type GRAPH_NODE = sig
  type t

  module Id : sig
    type t

    include S.JSONABLE with type t := t
    include S.COMPARABLE with type t := t

    module Map : sig
      include Map.S with type key := t

      val to_yojson : 'a Json.encoder -> 'a t Json.encoder
      val of_yojson : 'a Json.decoder -> 'a t Json.decoder
    end

    module Set : sig
      include Set.S with type elt := t
    end

  end

  val id : t -> Id.t

  include S.JSONABLE with type t := t
  include S.COMPARABLE with type t := t
end

module Make (Node : GRAPH_NODE) : GRAPH
  with
    type node = Node.t
    and type id = Node.Id.t
  = struct

  type node = Node.t
  type id = Node.Id.t

  type t = {
    root : Node.Id.t;
    nodes : payload Node.Id.Map.t;
  } [@@deriving yojson]

  and payload = {
    node : Node.t;
    dependencies : Node.Id.t list;
  }

  let empty root = {nodes = Node.Id.Map.empty; root}

  let add node dependencies graph =
    let payload = {node; dependencies;} in
    let nodes = Node.Id.Map.add (Node.id node) payload graph.nodes in
    {graph with nodes;}

  let find' id graph =
    match Node.Id.Map.find_opt id graph.nodes with
    | Some {node;dependencies;} -> Some (node, dependencies)
    | None -> None

  let findExn' id graph =
    let {node; dependencies;} = Node.Id.Map.find id graph.nodes in
    node, dependencies

  let root graph =
    let node, _ = findExn' graph.root graph in
    node

  let mem id graph = Node.Id.Map.mem id graph.nodes

  let dependencies node graph =
    let {dependencies; node = _;} = Node.Id.Map.find (Node.id node) graph.nodes in
    let f id = let node, _ = findExn' id graph in node in
    (List.map ~f dependencies)

  let allDependencies node graph =
    let rec visitNode (seen, acc) id =
      if Node.Id.Set.mem id seen
      then seen, acc
      else
        let {node; dependencies;} = Node.Id.Map.find id graph.nodes in
        let seen = Node.Id.Set.add id seen in
        let acc = node::acc in
        let seen, acc = visitDependencies (seen, acc) dependencies in
        seen, acc

    and visitDependencies (seen, acc) dependencies =
      List.fold_left ~f:visitNode ~init:(seen, acc) dependencies

    in

    let {dependencies; node = _;} =
      Node.Id.Map.find (Node.id node) graph.nodes
    in

    let _, dependencies =
      visitDependencies (Node.Id.Set.empty, []) dependencies
    in 
    dependencies

  let find id graph =
    match find' id graph with
    | Some (node, _) -> Some node
    | None -> None

  let findExn id graph =
    let node, _ = findExn' id graph in
    node

  let fold ~f ~init graph =
    let f _id payload v =
      let dependencies =
        let f id = let node, _ = findExn' id graph in node in
        List.map ~f payload.dependencies
      in
      f payload.node dependencies v
    in
    Node.Id.Map.fold f graph.nodes init

end
