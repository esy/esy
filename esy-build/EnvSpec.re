type t = {
  augmentDeps: option(EsyInstall.Solution.DepSpec.t),
  buildIsInProgress: bool,
  includeCurrentEnv: bool,
  includeBuildEnv: bool,
  includeEsyIntrospectionEnv: bool,
  includeNpmBin: bool,
};
