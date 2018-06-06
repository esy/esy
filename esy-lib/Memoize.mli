type ('k, 'v) t

val make :
  ?size:int
  -> unit
  -> ('k, 'v) t

val compute :
  ('k, 'v) t
  -> 'k
  -> ('k -> 'v)
  -> 'v
