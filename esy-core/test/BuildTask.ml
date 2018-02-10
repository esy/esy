open Esy

let cfg = {
  Config.
  esyVersion = "0.x.x";
  sandboxPath = Path.v "/tmp/__sandbox__";
  prefixPath = Path.v "/tmp/__prefix__";
  storePath = Path.v "/tmp/__store__";
  localStorePath = Path.v "/tmp/__local_store__";
}

module TestCommandExpr = struct
  let dep = Package.{
    id = "%dep%";
    name = "dep";
    version = "1.0.0";
    dependencies = [];
    buildCommands = None;
    installCommands = None;
    buildType = BuildType.InSource;
    sourceType = SourceType.Immutable;
    exportedEnv = [
      {
        ExportedEnv.
        name = "OK";
        value = "#{self.install / 'ok'}";
        exclusive = false;
        scope = Local;
      }
    ];
    sourcePath = Config.ConfigPath.ofPath cfg (Path.v "/path");
    resolution = None;
  }

  let pkg = Package.{
    id = "%pkg%";
    name = "pkg";
    version = "1.0.0";
    dependencies = [Dependency dep];
    buildCommands = Some [CommandList.Command.Unparsed "cp ./hello #{self.bin}"];
    installCommands = Some [CommandList.Command.Parsed ["cp"; "./man"; "#{self.man}"]];
    buildType = BuildType.InSource;
    sourceType = SourceType.Immutable;
    exportedEnv = [];
    sourcePath = Config.ConfigPath.ofPath cfg (Path.v "/path");
    resolution = None;
  }

  let task = BuildTask.ofPackage pkg

  let check f =
    match task with
    | Ok task ->
      f task
    | Error err ->
      print_endline (Run.formatError err);
      false

  let%test "#{self...} inside esy.build" =
    check (fun task ->
      let commands = BuildTask.CommandList.show task.buildCommands in
      commands = {|[["cp"; "./hello"; "%store%/s/%pkg%/bin"]]|}
    )

  let%test "#{self...} inside esy.install" =
    check (fun task ->
      let commands = BuildTask.CommandList.show task.installCommands in
      commands = {|[["cp"; "./man"; "%store%/s/%pkg%/man"]]|}
    )

  let%test "#{self...} inside esy.exportedEnv" =
    check (fun task ->
      let bindings = Environment.Closed.bindings task.env in
      let f = function
        | {Environment. name = "OK"; value = Value value; _} ->
          value = "%store%/i/%dep%/ok"
        | _ ->
          false
      in
      match ListLabels.find_opt ~f bindings with
      | Some _ -> true
      | None -> false
    )
end
