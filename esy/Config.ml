module Store = EsyLib.Store
module SandboxSpec = EsyInstall.SandboxSpec

type t = {
  spec : EsyInstall.SandboxSpec.t;
  buildCfg : EsyBuildPackage.Config.t;
}

let make
  ~prefixPath
  ~spec
  () =
  let value =
    let open Result.Syntax in

    let storePath =
      match prefixPath with
      | Some v -> EsyBuildPackage.Config.StorePathOfPrefix v
      | None -> EsyBuildPackage.Config.StorePathDefault
    in

    let%bind buildCfg =
      EsyBuildPackage.Config.make
        ~storePath
        ~projectPath:spec.SandboxSpec.path
        ~localStorePath:(EsyInstall.SandboxSpec.storePath spec)
        ~buildPath:(EsyInstall.SandboxSpec.buildPath spec)
        ()
    in

    return {
      spec;
      buildCfg;
    }
  in
  Run.ofBosError value
