val ofJson :
  ?parseResolutions:bool
  -> ?parseDevDependencies:bool
  -> ?source:EsyInstall.Source.t
  -> name:string
  -> version:EsyInstall.Version.t
  -> Json.t
  -> Package.t Run.t
