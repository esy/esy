open EsyPrimitives;
/** Given the solution and [fetchdepssubset], fetches npm packages of a [node] in the solution graph */
let getNPMChildren:
  (~solution: Solution.t, ~fetchDepsSubset: FetchDepsSubset.t, Solution.pkg) =>
  list(Package.t);
