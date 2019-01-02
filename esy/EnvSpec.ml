type t = {
  augmentDeps : EsyInstall.DepSpec.t option;
  buildIsInProgress : bool;
  includeCurrentEnv : bool;
  includeBuildEnv : bool;
  includeEsyIntrospectionEnv : bool;
  includeNpmBin : bool;
}
