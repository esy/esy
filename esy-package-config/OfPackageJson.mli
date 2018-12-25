type warning = string

(** Parse [InstallManifest.t] out of package.json data.
  *)
val installManifest :
  ?parseResolutions:bool
  -> ?parseDevDependencies:bool
  -> ?source:Source.t
  -> name:string
  -> version:Version.t
  -> Json.t
  -> (InstallManifest.t * warning list) Run.t

(** Parse [BuildManifest.t] out of package.json data.

    Note that some package.json data don't have build manifests defined. We
    return [None] in this case.

  *)
val buildManifest :
  Json.t
  -> (BuildManifest.t * warning list) option Run.t
