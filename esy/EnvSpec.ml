type t = {
  augmentDeps : DepSpec.t option;
  buildIsInProgress : bool;
  includeCurrentEnv : bool;
  includeBuildEnv : bool;
  includeNpmBin : bool;
}
