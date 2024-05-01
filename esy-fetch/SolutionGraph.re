open EsyPackageConfig;
type parent = option(Lazy.t(node))
and node = {
  parent,
  data: Solution.pkg,
};
let rec parentPp = (fmt, parentNode) => {
  switch (parentNode) {
  | Some(lazyParentNode) =>
    let parentNode = Lazy.force(lazyParentNode);
    Package.pp(fmt, parentNode.data);
  | None => Fmt.any("<no-parent>", fmt, ())
  };
}
and parentsPp = fmt => {
  let sep = fmt => Fmt.any(" -> ", fmt);
  Fmt.list(~sep, parentPp, fmt);
}
and nodePp = (fmt, node) => {
  let {parent, data} = node;
  Fmt.pf(
    fmt,
    "-- SolutionNode: --\ndata: %a\nParents: %a\n",
    Package.pp,
    data,
    parentPp,
    parent,
  );
};
type state = {
  queue: Queue.t(node),
  visited: PackageId.Map.t(bool),
};
let parent = ({parent, _}) => parent;
type traversalFn = Solution.pkg => list(Solution.pkg);
let isVisited = (visitedMap, node) => {
  visitedMap
  |> PackageId.Map.find_opt(node.Package.id)
  |> Stdlib.Option.value(~default=false);
};
let iterator = solution => {
  let queue = Queue.create();
  let root = Solution.root(solution);
  Queue.push({data: root, parent: None}, queue);
  let visited = PackageId.Map.empty;
  {queue, visited};
};
let take = (~traverse, iterable) => {
  let {queue, visited} = iterable;
  let dequeue = node => {
    let {data: pkg, _} = node;
    let f = childNode =>
      if (!isVisited(visited, childNode)) {
        Queue.push({parent: Some(lazy(node)), data: childNode}, queue);
      };
    pkg |> traverse |> List.iter(~f);
    let visited =
      PackageId.Map.update(pkg.Package.id, _ => Some(true), visited);
    (node, {queue, visited});
  };
  queue |> Queue.take_opt |> Option.map(~f=dequeue);
};
let debug = (~traverse, solution) => {
  let rec loop = iterableSolution => {
    switch (take(~traverse, iterableSolution)) {
    | Some((node, nextIterSolution)) =>
      print_endline(Format.asprintf("%a", nodePp, node));
      loop(nextIterSolution);
    | None => ()
    };
  };

  solution |> iterator |> loop;
};
