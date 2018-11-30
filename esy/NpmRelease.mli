val make :
  ocamlopt:Path.t
  -> outputPath:Path.t
  -> concurrency:int
  -> Plan.Sandbox.t
  -> unit RunAsync.t
(**
 * Produce an npm release for the [sandbox].
 *)
