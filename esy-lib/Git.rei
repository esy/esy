/**
 * Git repository manipulation.
 *
 * The implementation uses git command.
 */;

type ref = string;
type commit = string;
type remote = string;

/** Clone repository from [remote] into [dst] local path. */

let clone:
  (~branch: string=?, ~depth: int=?, ~dst: Fpath.t, ~remote: remote, unit) =>
  RunAsync.t(unit);

/** Pull into [repo] from [source] branch [branchSpec] */

let pull:
  (
    ~force: bool=?,
    ~ffOnly: bool=?,
    ~depth: int=?,
    ~remote: remote,
    ~repo: Fpath.t,
    ~branchSpec: remote,
    unit
  ) =>
  RunAsync.t(unit);

/** Checkout the [ref] in the [repo] */

let checkout: (~ref: ref, ~repo: Fpath.t, unit) => RunAsync.t(unit);

/** Resolve [ref] of the [remote] */

let lsRemote:
  (~ref: ref=?, ~remote: remote, unit) => RunAsync.t(option(commit));

let isCommitLike: string => bool;

module ShallowClone: {
  let update: (~branch: remote, ~dst: Fpath.t, remote) => RunAsync.t(unit);
};
