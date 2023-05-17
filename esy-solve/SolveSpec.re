open DepSpec;
open EsyPackageConfig;

[@deriving ord]
type t = {
  solveDev: SolveDepSpec.t,
  solveAll: SolveDepSpec.t,
};

let rec evalDepSpec = (manifest: InstallManifest.t, depspec: SolveDepSpec.t) => {
  open SolveDepSpec;
  module D = InstallManifest.Dependencies;
  Run.Syntax.(
    switch (depspec) {
    | Package(Self) => return(D.NpmFormula(NpmFormula.empty))
    | Dependencies(Self) => return(manifest.dependencies)
    | DevDependencies(Self) => return(manifest.devDependencies)
    | Union(a, b) =>
      let* adeps = evalDepSpec(manifest, a);
      let* bdeps = evalDepSpec(manifest, b);
      switch (adeps, bdeps) {
      | (D.NpmFormula(a), D.NpmFormula(b)) =>
        let reqs = NpmFormula.override(a, b);
        return(D.NpmFormula(reqs));
      | (D.OpamFormula(a), D.OpamFormula(b)) => return(D.OpamFormula(a @ b))
      | (_, _) =>
        errorf(
          "incompatible dependency formulas found at %a: %a and %a",
          InstallManifest.pp,
          manifest,
          pp,
          a,
          pp,
          b,
        )
      };
    }
  );
};

let eval = (spec, manifest) => {
  let depspec =
    switch (manifest.InstallManifest.source) {
    | Link({kind: LinkDev, _}) => spec.solveDev
    | Link({kind: LinkRegular, _})
    | Install(_) => spec.solveAll
    };

  evalDepSpec(manifest, depspec);
};
