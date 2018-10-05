module type GRAPH = sig
  type t
  type node
  type id

  val empty : id -> t
  val add : node -> id StringMap.t -> t -> t

  val root : t -> node
  val mem : id -> t -> bool
  val get : id -> t -> node option
  val getExn : id -> t -> node
  val find : (id -> node -> bool) -> t -> (id * node) option
  val dependencies : node -> t -> node StringMap.t
  val allDependencies : node -> t -> (bool * node) list

  val fold : f:(node -> node StringMap.t -> 'v -> 'v) -> init:'v -> t -> 'v

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
    dependencies : Node.Id.t StringMap.t;
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
    StringMap.map f dependencies

  let allDependencies node graph =
    let rec visitNode ~direct _label id (seen, acc) =
      if Node.Id.Set.mem id seen
      then seen, acc
      else
        let {node; dependencies;} = Node.Id.Map.find id graph.nodes in
        let seen = Node.Id.Set.add id seen in
        let acc = (direct, node)::acc in
        let seen, acc = visitDependencies ~direct:false dependencies (seen, acc) in
        seen, acc

    and visitDependencies ~direct dependencies (seen, acc) =
      StringMap.fold (visitNode ~direct) dependencies (seen, acc)

    in

    let {dependencies; node = _;} =
      Node.Id.Map.find (Node.id node) graph.nodes
    in

    let _, dependencies =
      visitDependencies ~direct:true dependencies (Node.Id.Set.empty, [])
    in
    dependencies

  let get id graph =
    match find' id graph with
    | Some (node, _) -> Some node
    | None -> None

  let getExn id graph =
    let node, _ = findExn' id graph in
    node

  let find f graph =
    let f id =
      let payload = Node.Id.Map.find id graph.nodes in
      f id payload.node
    in
    match Node.Id.Map.find_first_opt f graph.nodes with
    | None -> None
    | Some (id, payload) -> Some (id, payload.node)

  let fold ~f ~init graph =
    let f _id payload v =
      let dependencies =
        let f id =
          let {node; dependencies = _;} = Node.Id.Map.find id graph.nodes in
          node
        in
        StringMap.map f payload.dependencies
      in
      f payload.node dependencies v
    in
    Node.Id.Map.fold f graph.nodes init

end
