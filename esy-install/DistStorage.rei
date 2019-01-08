open EsyPackageConfig;

/**

    Storage for package dists.

 */;

let fetchIntoCache: (Config.t, SandboxSpec.t, Dist.t) => RunAsync.t(Path.t);

type fetchedDist;

let ofCachedTarball: Path.t => fetchedDist;
let ofDir: Path.t => fetchedDist;

let fetch: (Config.t, SandboxSpec.t, Dist.t) => RunAsync.t(fetchedDist);

let unpack: (fetchedDist, Path.t) => RunAsync.t(unit);

let cache: (fetchedDist, Path.t) => RunAsync.t(fetchedDist);
