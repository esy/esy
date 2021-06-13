open EsyPackageConfig;

module Id = {
  [@deriving ord]
  type t =
    | Self;

  let pp = fmt =>
    fun
    | Self => Fmt.unit("self", fmt, ());
};

include EsyInstall.DepSpecAst.Make(Id);

let self = Id.Self;

let rec eval = (manifest: InstallManifest.t, spec: t) => {
  module D = InstallManifest.Dependencies;
  Run.Syntax.(
    switch (spec) {
    | Package(Self) => return(D.NpmFormula(NpmFormula.empty))
    | Dependencies(Self) => return(manifest.dependencies)
    | DevDependencies(Self) => return(manifest.devDependencies)
    | Union(a, b) =>
      let* adeps = eval(manifest, a);
      let* bdeps = eval(manifest, b);
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

let rec toDepSpec = (spec: t) =>
  switch (spec) {
  | Package(Self) => EsyInstall.Solution.DepSpec.(package(self))
  | Dependencies(Self) => EsyInstall.Solution.DepSpec.(dependencies(self))
  | DevDependencies(Self) =>
    EsyInstall.Solution.DepSpec.(devDependencies(self))
  | Union(a, b) => EsyInstall.Solution.DepSpec.(toDepSpec(a) + toDepSpec(b))
  };
