/** Wrapper over OpamRegistry.t to create multiple registries */

type t = list(OpamRegistry.t)

let make: (~cfg: Config.t, unit) => t;
