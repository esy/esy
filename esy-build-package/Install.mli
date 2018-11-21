val install :
  trySymlink:bool
  -> rootPath:Fpath.t
  -> prefixPath:Fpath.t
  -> Fpath.t option -> (unit, _) Run.t
