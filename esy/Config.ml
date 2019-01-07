module Store = EsyLib.Store
module SandboxSpec = EsyInstall.SandboxSpec

type t = {
  spec : EsyInstall.SandboxSpec.t;
  buildCfg : EsyBuildPackage.Config.t;
}

let defaultPrefixPath = Path.v "~/.esy"

let make
  ~prefixPath
  ~spec
  () =
  let value =
    let open Result.Syntax in

    let prefixPath =
      match prefixPath with
      | Some v -> v
      | None ->
        let home = Path.homePath () in
        Path.(home / ".esy")
    in

    let%bind buildCfg =
      EsyBuildPackage.Config.make
        ~storePath:(StorePathOfPrefix prefixPath)
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
