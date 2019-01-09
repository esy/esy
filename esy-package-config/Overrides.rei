type t = list(Override.t);

let empty: t;
let isEmpty: t => bool;

let add: (Override.t, t) => t;
/* [add override overrides] adds single [override] on top of [overrides]. */

let addMany: (list(Override.t), t) => t;
/* [add override_list overrides] adds many [overridea_list] overrides on top of [overrides]. */

let merge: (t, t) => t;
/* [merge newOverrides overrides] adds [newOverrides] on top of [overrides]. */

let foldWithBuildOverrides:
  (~f: ('v, Override.build) => 'v, ~init: 'v, t) => RunAsync.t('v);

let foldWithInstallOverrides:
  (~f: ('v, Override.install) => 'v, ~init: 'v, t) => RunAsync.t('v);
