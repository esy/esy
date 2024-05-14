/**
   Checks if a [nodeModuleEntry] can be hoisted under the last element
   in [hypotheticalLineage].

   Notes:

   We only need the most recent ancestor to know where in the graph we
   can place the incoming [nodeModuleEntry]. Begs the question: why
   work with the entire lineage? Because it helps a traverse the graph
   more efficiently.

*/
module type S = {
  /**
     [data] represents variable, one of which is Package.t
     parameterising over Package.t with [data] is how we keep it out of our abstractions.
   */
  type data;

  /** Represents the hoisted node_module graph. Each node's id is the package name (not version) */
  type hoistedGraph;

  /** Represents the entry/node in hoisted node_module. See [hoistedGraph('a)] for more details */
  type hoistedGraphNode;

  /** Type representing errors from the module handling node_modules */
  type hoistedGraphErrors;

  /**
     Takes a named list [hypotheticalLineage] of type [data], a
     [hoistedGraph(data)] named [hoistedGraph], and a node
     which can be [hoistedGraph]'s node (but not necessarily so).
     Returns if it can become a node indeed.
  */
  let hoist:
    (
      ~hypotheticalLineage: list(data),
      ~hoistedGraph: hoistedGraph,
      hoistedGraphNode
    ) =>
    result(hoistedGraph, hoistedGraphErrors);

  let hoistLineage:
    (~lineage: list(data), ~hoistedGraph: hoistedGraph, hoistedGraphNode) =>
    result(hoistedGraph, string);
};

module type Data = {
  include Map.OrderedType;
  let sameVersion: (t, t) => int;
};

module Make =
       (
         K: Data,
         HoistedNodeModulesGraph:
           HoistedNodeModulesGraph.S with type data = K.t,
       )

         : (
           S with
             type hoistedGraph = HoistedNodeModulesGraph.t and
             type hoistedGraphNode = HoistedNodeModulesGraph.node and
             type hoistedGraphErrors = HoistedNodeModulesGraph.Errors.t and
             type data = K.t
       ) => {
  type data = K.t;
  type hoistedGraph = HoistedNodeModulesGraph.t;
  type hoistedGraphNode = HoistedNodeModulesGraph.node;
  type hoistedGraphErrors = HoistedNodeModulesGraph.Errors.t;

  let rec proceedMatching = (~root: hoistedGraphNode, ~lineage, ~targetNode) => {
    let children = Lazy.force(root.children);
    switch (lineage) {
    | [] =>
      let dataField = HoistedNodeModulesGraph.nodeData(targetNode);
      switch (HoistedNodeModulesGraph.Map.find_opt(dataField, children)) {
      | Some(existingChild) =>
        if (K.sameVersion(dataField, existingChild.data) == 0) {
          Ok(root);
        } else {
          Error(`Package_name_conflict);
        }
      | None =>
        Ok(
          HoistedNodeModulesGraph.nodeUpdateChildren(
            dataField,
            targetNode,
            root,
          ),
        )
      };
    | [h, ...r] =>
      switch (HoistedNodeModulesGraph.Map.find_opt(h, children)) {
      | Some(child) =>
        switch (proceedMatching(~root=child, ~lineage=r, ~targetNode)) {
        | Ok(newChild) =>
          Ok(HoistedNodeModulesGraph.nodeUpdateChildren(h, newChild, root))
        | Error(e) => Error(e)
        }
      | None =>
        let child =
          HoistedNodeModulesGraph.makeNode(
            ~parent=Some(lazy(root)),
            ~data=h,
          );
        let updatedRoot =
          HoistedNodeModulesGraph.nodeUpdateChildren(h, child, root);
        proceedMatching(~root=updatedRoot, ~lineage=[h, ...r], ~targetNode);
      }
    };
  };

  let hoist = (~hypotheticalLineage, ~hoistedGraph, node) => {
    let roots = HoistedNodeModulesGraph.roots(hoistedGraph);
    switch (hypotheticalLineage) {
    | [h, ...rest] =>
      switch (HoistedNodeModulesGraph.Map.find_opt(h, roots)) {
      | Some(hoistedGraphRoot) =>
        switch (
          proceedMatching(
            ~root=hoistedGraphRoot,
            ~lineage=rest,
            ~targetNode=node,
          )
        ) {
        | Ok(newRoot) =>
          HoistedNodeModulesGraph.Map.update(h, _ => Some(newRoot), roots)
          |> HoistedNodeModulesGraph.ofRoots
          |> Result.return
        | Error(e) => Error(e)
        }
      | None => Error(`Lineage_with_unknown_roots)
      }
    | [] => Error(`Empty_lineage)
    };
  };

  /**
       Notes:
     We got rid of Queue.t since we endup traversing it immmediately. It was stateful and
     tricky to reason about.
       [hypotheticalLineage] can initially be empty, but should never return empty


     TODO: lineage == [] could mean,
     1. we finished processing lineage
     2. node has no parents

     This is unfortunate. And needs a hack to work around. Lazy lineage computation would solve this.
 */
  let rec hoistLineage' =
          (~hypotheticalLineage, ~lineage, ~hoistedGraph, node) => {
    switch (lineage) {
    | [head, ...rest] =>
      let hypotheticalLineage = hypotheticalLineage @ [head];
      switch (hoist(~hypotheticalLineage, ~hoistedGraph, node)) {
      | Ok(hoistedGraph) => Ok(hoistedGraph)
      | Error(`Package_name_conflict) =>
        // Workaround to make sure we dont recurse as we have finished through
        // the lineage. See notes in docstring
        if (List.length(rest) > 0) {
          hoistLineage'(
            ~hypotheticalLineage,
            ~hoistedGraph,
            ~lineage=rest,
            node,
          );
        } else {
          Ok(hoistedGraph);
        }
      | Error(`Empty_lineage as e)
      | Error(`Lineage_with_unknown_roots as e) =>
        Error(HoistedNodeModulesGraph.Errors.toString(e))
      };
    | [] =>
      // HACK! TODO remove this
      // This should only be done when a node has empty lineage.
      // not because we kept recursing and ran out of lineage.
      // See notes in the docstring
      Ok(HoistedNodeModulesGraph.addRoot(~node, hoistedGraph))
    };
  };
  let hoistLineage = hoistLineage'(~hypotheticalLineage=[]);
};
