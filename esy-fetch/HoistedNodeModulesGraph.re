/**

   Represents a hoisted, shallower, graph of node modules.

   Designed to easily detach node module deeper in the tree,
   possibly a duplicate, and place them near to root. By doing
   so, more than one node modules that need them can see them.

   Initially written in a way that resembles, [SolutionGraph.t],
   but, after all the iteration, [parent] field may not be needed
   anymore.

*/
module type S = {
  /**
     [data] represents variable, one of which is Package.t
     parameterising over Package.t with [data] is how we keep it out of our abstractions.
   */
  type data;

  /**

     This maps contain keys that represent node module
     entries. Packages with same name are equal (even if different
     versions).

     Note about why [S.Map] isn't parameterised on both k and v
     https://stackoverflow.com/questions/14629642/ocaml-polymorphic-function-on-maps-with-generic-keys

   */
  module Map: Map.S with type key = data;
  type t = Map.t(node) // likely a map of root nodes
  and node = {
    parent: option(Lazy.t(node)),
    data,
    children: Lazy.t(Map.t(node)),
  };
  let parent: node => option(Lazy.t(node));
  let roots: t => Map.t(node);
  let ofRoots: Map.t(node) => t;
  let nodeUpdateChildren: (data, node, node) => node;
  let nodeData: node => data;
  let makeNode: (~parent: option(Lazy.t(node)), ~data: data) => node;
  let nodePp: Fmt.t(node);
  let dataListPp: Fmt.t(list(data));
  let addRoot: (~node: node, t) => t;
  module Errors: {
    type t = [
      | `Empty_lineage
      | `Lineage_with_unknown_roots
      | `Package_name_conflict
    ];
    let toString: t => string;
  };
};

module Errors = {
  type t = [
    | `Empty_lineage
    | `Lineage_with_unknown_roots
    | `Package_name_conflict
  ];
  let toString =
    fun
    | `Empty_lineage => "hypotheticalLineage should not be empty"
    | `Lineage_with_unknown_roots => "Lineage doesn't start with known roots"
    | `Package_name_conflict => "Package with same name exists among the children";
};

type data = NodeModule.t;
let traversalFn = ref(_ => []);
module Map = Map.Make(NodeModule);
type t = Map.t(node)
and node = {
  parent: option(Lazy.t(node)),
  data,
  children: Lazy.t(Map.t(node)),
};

let dataListPp = (fmt, data) => {
  let sep = fmt => Fmt.any(" -- ", fmt);
  if (List.length(data) == 0) {
    Fmt.any("<empty>", fmt, ());
  } else {
    data |> Fmt.list(~sep, Package.pp, fmt);
  };
};

let parent = ({parent, _}) => parent;
let rec parentPp = (fmt, parentNode) => {
  switch (parentNode) {
  | Some(parentNode) =>
    let parentNode = Lazy.force(parentNode);
    NodeModule.pp(fmt, parentNode.data);
  | None => Fmt.any("<no-parent>", fmt, ())
  };
}
and parentsPp = fmt => {
  let sep = fmt => Fmt.any(" -> ", fmt);
  Fmt.list(~sep, parentPp, fmt);
}
and childPp = NodeModule.pp
and childrenPp = (fmt, children) => {
  let sep = fmt => Fmt.any(" -- ", fmt);
  let childrenAsList =
    children
    |> Lazy.force
    |> Map.bindings
    |> List.map(~f=((child, _true)) => child);
  if (List.length(childrenAsList) == 0) {
    Fmt.any("<no-children>", fmt, ());
  } else {
    childrenAsList |> Fmt.list(~sep, childPp, fmt);
  };
}
and nodePp = (fmt, node) => {
  let {parent, data, children} = node;
  Fmt.pf(
    fmt,
    "-- HoistedNodeModulesGraph: --\ndata: %a\nParent: %a\nChildren: %a",
    NodeModule.pp,
    data,
    parentPp,
    parent,
    childrenPp,
    children,
  );
};

let roots = roots => roots;
let empty = Map.empty;
let ofRoots = roots => roots;
let nodeUpdateChildren = (dataField, newNode, parent) => {
  let newNode = {...newNode, parent: Some(lazy(parent))};
  {
    ...parent,
    children: lazy(Map.add(dataField, newNode, Lazy.force(parent.children))),
  };
};
let nodeData = node => node.data;

let makeCache: Hashtbl.t(data, node) = Hashtbl.create(100);
let rec makeNode' = (~parent, ~data) => {
  let init = Map.empty;
  let f = (acc, child) => {
    Map.add(
      child,
      makeNode(~parent=Some(lazy(makeNode(~parent, ~data))), ~data=child),
      acc,
    );
  };
  {
    parent,
    data,
    children: lazy(List.fold_left(~f, ~init, traversalFn^(data))),
  };
}
and makeNode: (~parent: option(Lazy.t(node)), ~data: data) => node =
  (~parent, ~data) => {
    switch (Hashtbl.find_opt(makeCache, data)) {
    | Some(node) => node
    | None => makeNode'(~parent, ~data)
    };
  };

let addRoot = (~node, graph) => {
  Map.add(node.data, node, graph);
};

type state = {
  queue: Queue.t(node),
  visited: Map.t(bool),
};
let isVisited = (visitedMap, node) => {
  visitedMap |> Map.find_opt(node) |> Stdlib.Option.value(~default=false);
};
let iterator = graph => {
  let queue = Queue.create();
  let roots = roots(graph);
  roots
  |> Map.bindings
  |> List.iter(~f=((_data, root)) => {Queue.push(root, queue)});
  let visited = Map.empty;
  {queue, visited};
};

let take = iterable => {
  let {queue, visited} = iterable;
  let dequeue = node => {
    let {data: pkg, _} = node;
    let f = node =>
      if (!isVisited(visited, node.data)) {
        Queue.push(node, queue);
      };
    node.children
    |> Lazy.force
    |> Map.bindings
    |> List.map(~f=((_k, v)) => v)
    |> List.iter(~f);
    let visited = Map.update(pkg, _ => Some(true), visited);
    (node, {queue, visited});
  };
  queue |> Queue.take_opt |> Option.map(~f=dequeue);
};

let init = (~traverse: 'a => list('a)) => {
  traversalFn := traverse;
  empty;
};
