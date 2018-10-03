module type GRAPH = sig
  type t
  type node
  type id

  val empty : id -> t
  val add : node -> id list -> t -> t

  val root : t -> node
  val mem : id -> t -> bool
  val find : id -> t -> node option
  val dependencies : node -> t -> node list

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
    match Node.Id.Map.find_opt id graph.nodes with
    | Some {node;dependencies;} -> node, dependencies
    | None -> raise Not_found

  let root graph =
    let node, _ = findExn' graph.root graph in
    node

  let mem id graph = Node.Id.Map.mem id graph.nodes

  let dependencies node graph =
    let {dependencies; node = _;} = Node.Id.Map.find (Node.id node) graph.nodes in
    let f id = let node, _ = findExn' id graph in node in
    (List.map ~f dependencies)

  let find id graph =
    match find' id graph with
    | Some (node, _) -> Some node
    | None -> None

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
