module type GRAPH = {
  type t;
  type node;
  type id;
  type traverse = node => list(id);

  let empty: id => t;
  let add: (t, node) => t;
  let nodes: t => list(node);

  let mem: (t, id) => bool;
  let isRoot: (t, node) => bool;

  let root: t => node;
  let get: (t, id) => option(node);
  let getExn: (t, id) => node;
  let findBy: (t, (id, node) => bool) => option((id, node));
  let dependencies: (~traverse: traverse=?, t, node) => list(node);
  let allDependenciesBFS:
    (~traverse: traverse=?, ~dependencies: list(id)=?, t, id) =>
    list((bool, node));

  let fold: (~f: (node, list(node), 'v) => 'v, ~init: 'v, t) => 'v;
};

module type GRAPH_NODE = {
  type t;

  module Id: {
    type t;

    include S.COMPARABLE with type t := t;

    module Map: {include Map.S with type key := t;};

    module Set: {include Set.S with type elt := t;};
  };

  let id: t => Id.t;
  let traverse: t => list(Id.t);

  include S.COMPARABLE with type t := t;
};

module Make =
       (Node: GRAPH_NODE)
       : (GRAPH with type node = Node.t and type id = Node.Id.t) => {
  type node = Node.t;
  type id = Node.Id.t;
  type traverse = node => list(id);

  type t = {
    root: Node.Id.t,
    nodes: Node.Id.Map.t(Node.t),
  };

  let empty = root => {nodes: Node.Id.Map.empty, root};

  let add = (graph, node) => {
    let nodes = Node.Id.Map.add(Node.id(node), node, graph.nodes);
    {...graph, nodes};
  };

  let get = (graph, id) => Node.Id.Map.find_opt(id, graph.nodes);

  let getExn = (graph, id) => Node.Id.Map.find(id, graph.nodes);

  let root = graph => getExn(graph, graph.root);

  let isRoot = (graph, node) =>
    Node.Id.compare(Node.id(node), graph.root) == 0;

  let mem = (graph, id) => Node.Id.Map.mem(id, graph.nodes);

  let nodes = graph => {
    let f = ((_, node)) => node;
    List.map(~f, Node.Id.Map.bindings(graph.nodes));
  };

  let dependencies = (~traverse=Node.traverse, graph, node) => {
    let dependencies = traverse(node);
    let f = id => getExn(graph, id);
    List.map(~f, dependencies);
  };

  let allDependenciesBFS =
      (~traverse=Node.traverse, ~dependencies=?, graph, id) => {
    let queue = Queue.create();
    let enqueue = (direct, dependencies) => {
      let f = id => Queue.add((direct, id), queue);
      List.iter(~f, dependencies);
    };

    let rec process = ((seen, dependencies)) =>
      switch (Queue.pop(queue)) {
      | exception Queue.Empty => (seen, dependencies)
      | (direct, id) =>
        if (Node.Id.Set.mem(id, seen)) {
          process((seen, dependencies));
        } else {
          let node = Node.Id.Map.find(id, graph.nodes);
          let seen = Node.Id.Set.add(id, seen);
          let dependencies = [(direct, node), ...dependencies];
          enqueue(false, traverse(node));
          process((seen, dependencies));
        }
      };

    let (_, dependencies) = {
      let dependencies =
        switch (dependencies) {
        | None =>
          let node = Node.Id.Map.find(id, graph.nodes);
          Node.traverse(node);
        | Some(dependencies) => dependencies
        };

      enqueue(true, dependencies);
      process((Node.Id.Set.empty, []));
    };

    List.rev(dependencies);
  };

  let findBy = (graph, f) => {
    let f = ((id, node)) => f(id, node);
    let bindings = Node.Id.Map.bindings(graph.nodes);
    List.find_opt(~f, bindings);
  };

  let fold = (~f, ~init, graph) => {
    let f = (_id, node, v) => {
      let dependencies = {
        let f = id => Node.Id.Map.find(id, graph.nodes);

        List.map(~f, Node.traverse(node));
      };

      f(node, dependencies, v);
    };

    Node.Id.Map.fold(f, graph.nodes, init);
  };
};
