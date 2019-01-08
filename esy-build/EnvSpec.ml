type t = {
  augmentDeps : EsyInstall.Solution.DepSpec.t option;
  buildIsInProgress : bool;
  includeCurrentEnv : bool;
  includeBuildEnv : bool;
  includeEsyIntrospectionEnv : bool;
  includeNpmBin : bool;
}
