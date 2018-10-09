(**

  This is the implementation of pnp map.

  The code is taken from yarn which has BSD2 license.

  Thanks yarn team.

 *)

val render :
  solution:Solution.t
  -> installation:Installation.t
  -> sandbox:SandboxSpec.t
  -> unit
  -> string
