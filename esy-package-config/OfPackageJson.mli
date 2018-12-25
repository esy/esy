val installManifest :
  ?parseResolutions:bool
  -> ?parseDevDependencies:bool
  -> ?source:Source.t
  -> name:string
  -> version:Version.t
  -> Json.t
  -> InstallManifest.t Run.t
