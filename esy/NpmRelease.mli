val make :
  sandboxEnv:BuildManifest.Env.item StringMap.t
  -> solution:EsyInstall.Solution.t
  -> installation:EsyInstall.Installation.t
  -> ocamlopt:Path.t
  -> outputPath:Path.t
  -> concurrency:int
  -> cfg:Config.t
  -> unit
  -> unit RunAsync.t
(**
 * Produce an npm release for the [sandbox].
 *)
