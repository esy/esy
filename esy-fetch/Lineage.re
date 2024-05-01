module type M = {
  type node;
  let parent: node => option(Lazy.t(node));
};

module type S = {
  type t;
  let constructLineage: t => list(t);
};

module Make = (M: M) : (S with type t := M.node) => {
  let rec constructLineage' = (acc, node) => {
    switch (M.parent(node)) {
    | Some(parent) =>
      let parent = Lazy.force(parent);
      constructLineage'([parent, ...acc], parent);
    | None => acc
    };
  };

  /** Returns a list of parents (lineage) starting from oldest ancestor first */
  let constructLineage = constructLineage'([]);
};
