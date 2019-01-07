module Store = EsyLib.Store
module SandboxSpec = EsyInstall.SandboxSpec

type t = {
  spec : EsyInstall.SandboxSpec.t;
  installCfg : EsyInstall.Config.t;
  buildCfg : EsyBuildPackage.Config.t;
}

let defaultPrefixPath = Path.v "~/.esy"

let make
  ~installCfg
  ~prefixPath
  ~spec
  () =
  let value =
    let open Result.Syntax in

    let%bind prefixPath =
      match prefixPath with
      | Some v -> return v
      | None ->
        let home = Path.homePath () in
        return Path.(home / ".esy")
    in

    let%bind padding = Store.getPadding(prefixPath) in
    let storePath = Path.(prefixPath / (Store.version ^ padding)) in
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
      installCfg;
      buildCfg;
    }
  in
  Run.ofBosError value
