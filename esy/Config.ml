module Store = EsyLib.Store
module SandboxSpec = EsyI.SandboxSpec

type t = {
  esyVersion : string;
  spec : EsyI.SandboxSpec.t;
  installCfg : EsyI.Config.t;
  buildCfg : EsyBuildPackage.Config.t;
}

let defaultPrefixPath = Path.v "~/.esy"

let make
  ~installCfg
  ~esyVersion
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
        ~localStorePath:(EsyI.SandboxSpec.storePath spec)
        ~buildPath:(EsyI.SandboxSpec.buildPath spec)
        ()
    in

    return {
      esyVersion;
      spec;
      installCfg;
      buildCfg;
    }
  in
  Run.ofBosError value
