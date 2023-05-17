open DepSpec;

/**
   Possible subsets of dependencies of a solution that can be installed
   Currently, they are [all] and [dev]. This could be, in future, [build].
   If peer dependencies and optional dependencies were supported, they'd be
   [{ ...peerDeps: FetchDepsSpect.t, optional: FetchDepsSpec.t}]
 */

type t = {
  /***
   Define how we traverse packages.
   */
  all: FetchDepSpec.t,
  /***
   Define how we traverse packages "in-dev".
   */
  dev: FetchDepSpec.t,
};

let everything: t;
