open EsyPackageConfig;

[@deriving ord]
type t = {
  solveDev: DepSpec.t,
  solveAll: DepSpec.t,
};

let eval = (spec, manifest) => {
  let depspec =
    switch (manifest.InstallManifest.source) {
    | Link({kind: LinkDev, _}) => spec.solveDev
    | Link({kind: LinkRegular, _})
    | Install(_) => spec.solveAll
    };

  DepSpec.eval(manifest, depspec);
};
