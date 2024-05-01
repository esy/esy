/** Abstract value to help provide a iterator API into solution graph */
type state;

type parent = option(Lazy.t(node))
and node = {
  parent,
  data: Solution.pkg,
};

let parent: node => parent;
let nodePp: Fmt.t(node);
let parentPp: Fmt.t(parent);
let parentsPp: Fmt.t(list(parent));

type traversalFn = Solution.pkg => list(Solution.pkg);

/** Setup a stateful interator */
let iterator: Solution.t => state;

/** Pop from the current item being traversed */
let take: (~traverse: traversalFn, state) => option((node, state));

let debug: (~traverse: traversalFn, Solution.t) => unit;

/* TODO [iterator] doesn't need Solution.t. It just needs a root (which is Package.t). Everything else is lazy (on-demand) */
