open DepSpec;

type t = {
  augmentDeps: option(FetchDepSpec.t),
  buildIsInProgress: bool,
  includeCurrentEnv: bool,
  includeBuildEnv: bool,
  includeEsyIntrospectionEnv: bool,
  includeNpmBin: bool,
};
