module Store = EsyLib.Store

type t = {
  esyVersion : string;
  prefixPath : Path.t;
  storePath : Path.t;
  fastreplacestringCommand : Cmd.t;
  esyBuildPackageCommand : Cmd.t;
}

let defaultPrefixPath = Path.v "~/.esy"

let create
  ~fastreplacestringCommand
  ~esyBuildPackageCommand
  ~esyVersion
  ~prefixPath
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

    return {
      esyVersion;
      prefixPath;
      storePath;
      fastreplacestringCommand;
      esyBuildPackageCommand;
    }
  in
  Run.ofBosError value

