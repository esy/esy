open EsyPackageConfig

(**

  This is the implementation of pnp map.

  The code is taken from yarn which has BSD2 license.

  Thanks yarn team.

 *)

val render :
  basePath:Path.t
  -> rootPath:Path.t
  -> rootId:PackageId.t
  -> solution:Solution.t
  -> installation:Installation.t
  -> unit
  -> string
