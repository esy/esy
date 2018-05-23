(**
 * Produce an npm release for the [sandbox].
 *)
val make :
  outputPath:Path.t
  -> concurrency:int
  -> cfg:Config.t
  -> sandbox:Sandbox.t
  -> unit RunAsync.t
