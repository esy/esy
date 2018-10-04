module Task : sig
  type t = {
    id : string;
    name : string;
    version : EsyInstall.Version.t;
    env : Sandbox.Environment.t;
    buildCommands : Sandbox.Value.t list list;
    installCommands : Sandbox.Value.t list list;
    sourceType : Manifest.SourceType.t;
    buildScope : Scope.t;
    exportedScope : Scope.t;
    platform : System.Platform.t;
  }
end

type t = Task.t EsyInstall.PackageId.Map.t

val make :
  platform : System.Platform.t
  -> buildConfig:Sandbox.Value.ctx
  -> sandboxEnv:Manifest.Env.item StringMap.t
  -> solution:EsyInstall.Solution.t
  -> installation:EsyInstall.Installation.t
  -> unit
  -> Task.t option RunAsync.t
