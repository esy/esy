type reasons

val explain :
  cudfMapping:Universe.CudfMapping.t
  -> root:Package.t
  -> Cudf.cudf
  -> reasons Run.t

val ppReasons : reasons Fmt.t
