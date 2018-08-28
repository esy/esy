module Store = EsyLib.Store

type t = {
  buildConfig : EsyBuildPackage.Config.t;
  esyVersion : string;
  prefixPath : Path.t;
  fastreplacestringCommand : Cmd.t;
  esyBuildPackageCommand : Cmd.t;
}

type config = t

let defaultPrefixPath = Path.v "~/.esy"

let initStore (path: Path.t) =
  let open RunAsync.Syntax in
  let%bind () = Fs.createDir(Path.(path / "i")) in
  let%bind () = Fs.createDir(Path.(path / "b")) in
  let%bind () = Fs.createDir(Path.(path / "s")) in
  return ()

let create
  ~fastreplacestringCommand
  ~esyBuildPackageCommand
  ~esyVersion
  ~prefixPath (sandboxPath : Path.t) =
  let value =
    let open Result.Syntax in

    let%bind prefixPath =
      match prefixPath with
      | Some v -> return v
      | None ->
        let%bind home = Bos.OS.Dir.user() in
        return Path.(home / ".esy")
    in

    let%bind buildConfig =
      EsyBuildPackage.Config.make
        ~prefixPath
        ~sandboxPath
        ()
    in

    return {
      buildConfig;
      esyVersion;
      prefixPath;
      fastreplacestringCommand;
      esyBuildPackageCommand;
    }
  in
  Run.ofBosError value

let init cfg =
  let open RunAsync.Syntax in
  let%bind () = initStore cfg.buildConfig.storePath in
  let%bind () = initStore cfg.buildConfig.localStorePath in
  let%bind () =
    let storeLinkPath = Path.(cfg.prefixPath / Store.version) in
    if%bind Fs.exists storeLinkPath
    then return ()
    else Fs.symlink ~src:cfg.buildConfig.storePath storeLinkPath
  in
  return ()

module Value = EsyBuildPackage.Config.Value
module Environment = EsyBuildPackage.Config.Environment
module Path = EsyBuildPackage.Config.Path
