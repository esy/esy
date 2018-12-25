open EsyPackageConfig

val ofJson :
  ?parseResolutions:bool
  -> ?parseDevDependencies:bool
  -> ?source:Source.t
  -> name:string
  -> version:Version.t
  -> Json.t
  -> Package.t Run.t
