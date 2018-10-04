module Task : sig

  type t = {
    id : string;
    name : string;
    version : EsyInstall.Version.t;
    env : Sandbox.Environment.t;
    buildCommands : Sandbox.Value.t list list;
    installCommands : Sandbox.Value.t list list;
    buildType : Manifest.BuildType.t;
    sourceType : Manifest.SourceType.t;
    sourcePath : Sandbox.Path.t;
    buildScope : Scope.t;
    exportedScope : Scope.t;
    platform : System.Platform.t;
  }

end

type t =
  Task.t option EsyInstall.PackageId.Map.t
(** A collection of tasks. *)

val make :
  platform : System.Platform.t
  -> buildConfig:Sandbox.Value.ctx
  -> sandboxEnv:Manifest.Env.item StringMap.t
  -> solution:EsyInstall.Solution.t
  -> installation:EsyInstall.Installation.t
  -> unit
  -> t RunAsync.t

val plan : Task.t -> EsyBuildPackage.Plan.t
