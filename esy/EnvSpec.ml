type t = {
  augmentDeps : DepSpec.t option;
  buildIsInProgress : bool;
  includeCurrentEnv : bool;
  includeBuildEnv : bool;
  includeEsyIntrospectionEnv : bool;
  includeNpmBin : bool;
} [@@deriving yojson]
