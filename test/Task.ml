open Esy
module Cmd = EsyLib.Cmd
module Path = EsyLib.Path
module Run = EsyLib.Run
module System = EsyLib.System

let cfg =
  let prefixPath = Path.v "/tmp/__prefix__" in
  let storePath = Path.v "/tmp/__prefix__/store" in
  {
    Config.
    esyVersion = "0.x.x";
    prefixPath;
    storePath;
    fastreplacestringCommand = Cmd.v "fastreplacestring.exe";
    esyBuildPackageCommand = Cmd.v "esy-build-package";
  }

let buildConfig =
  let open EsyBuildPackage in
  Run.runExn (
    Config.make
      ~projectPath:(Path.v "/project")
      ~storePath:(Path.v "/store")
      ~localStorePath:(Path.v "/local-store")
      ~buildPath:(Path.v "/build")
      ())

let makeSandbox root dependencies =
  let dependencies =
    Sandbox.Package.Map.(
      empty
      |> add root dependencies
    )
  in
  {
    Sandbox.
    spec = {
      EsyLib.SandboxSpec.
      path = Path.v "/sandbox";
      manifest = EsyLib.SandboxSpec.ManifestSpec.Esy "package.json";
    };
    cfg;
    buildConfig;
    scripts = Manifest.Scripts.empty;
    env = Manifest.Env.empty;
    root;
    dependencies;
  }

module TestCommandExpr = struct

  let commandsEqual = [%derive.eq: string list list]
  let checkCommandsEqual commands expectation =
    let commands = List.map (List.map Sandbox.Value.toString) commands in
    commandsEqual commands expectation

  let dep = Sandbox.Package.{
    id = "%dep%";
    name = "dep";
    version = "1.0.0";
    build = {
      Manifest.Build.
      buildCommands = EsyCommands None;
      installCommands = EsyCommands None;
      patches = [];
      substs = [];
      buildType = Manifest.BuildType.InSource;
      sourceType = Manifest.SourceType.Immutable;
      exportedEnv = [
        {
          Manifest.ExportedEnv.
          name = "OK";
          value = "#{self.install / 'ok'}";
          exclusive = false;
          scope = Local;
        };
        {
          Manifest.ExportedEnv.
          name = "OK_BY_NAME";
          value = "#{dep.install / 'ok-by-name'}";
          exclusive = false;
          scope = Local;
        }
      ];
      buildEnv = [];
    };
    sourcePath = Sandbox.Path.v "/path";
    originPath = Path.Set.empty;
    source = None;
  }

  let pkg = Sandbox.Package.{
    id = "%pkg%";
    name = "pkg";
    version = "1.0.0";
    build = {
      Manifest.Build.
      buildCommands = EsyCommands (Some [
        Manifest.Command.Unparsed "cp ./hello #{self.bin}";
        Manifest.Command.Unparsed "cp ./hello2 #{pkg.bin}";
      ]);
      installCommands = EsyCommands (Some [
        Manifest.Command.Parsed ["cp"; "./man"; "#{self.man}"]
      ]);
      patches = [];
      substs = [];
      buildType = Manifest.BuildType.InSource;
      sourceType = Manifest.SourceType.Immutable;
      exportedEnv = [];
      buildEnv = [];
    };
    originPath = Path.Set.empty;
    sourcePath = Sandbox.Path.v "/path";
    source = None;
  }

  let dependencies = [Ok (Sandbox.Dependency.Dependency, dep)]

  let check ?platform sandbox f =
    match Task.ofSandbox ?platform sandbox with
    | Ok task ->
      f task
    | Error err ->
      print_endline (Run.formatError err);
      false

  let%test "#{...} inside esy.build" =
    check (makeSandbox pkg dependencies) (fun task ->
      let plan = Task.plan task in
      let id = Task.id task in
      checkCommandsEqual
        plan.EsyBuildPackage.Plan.build
        [
          ["cp"; "./hello"; "%{store}%/s/" ^ id ^ "/bin"];
          ["cp"; "./hello2"; "%{store}%/s/" ^ id ^ "/bin"];
        ]
    )

  let%test "#{...} inside esy.build / esy.install (depends on os)" =
    let pkg = Sandbox.Package.{
      pkg with
      build = {
        pkg.build with
        buildCommands = EsyCommands (Some [
          Manifest.Command.Unparsed "#{os == 'linux' ? 'apt-get install pkg' : 'true'}";
        ]);
        installCommands = EsyCommands (Some [
          Manifest.Command.Unparsed "make #{os == 'linux' ? 'install-linux' : 'install'}";
        ]);
        buildType = Manifest.BuildType.InSource;
      }
    } in
    check ~platform:System.Platform.Linux (makeSandbox pkg dependencies) (fun task ->
      let plan = Task.plan task in
      checkCommandsEqual
        plan.EsyBuildPackage.Plan.build
        [["apt-get"; "install"; "pkg"]]
      &&
      checkCommandsEqual
        plan.EsyBuildPackage.Plan.install
        [["make"; "install-linux"]]
    )
    &&
    check ~platform:System.Platform.Darwin (makeSandbox pkg dependencies) (fun task ->
      let plan = Task.plan task in
      checkCommandsEqual
        plan.EsyBuildPackage.Plan.build
        [["true"]]
      &&
      checkCommandsEqual
        plan.EsyBuildPackage.Plan.install
        [["make"; "install"]]
    )

  let%test "#{self...} inside esy.install" =
    check (makeSandbox pkg dependencies) (fun task ->
      let id = Task.id task in
      let plan = Task.plan task in
      checkCommandsEqual
        plan.EsyBuildPackage.Plan.install
        [["cp"; "./man"; "%{store}%/s/" ^ id ^ "/man"]]
    )

  let%test "#{...} inside esy.exportedEnv" =
    check (makeSandbox pkg dependencies) (fun task ->
      let [Task.Dependency, dep] =
        Task.dependencies task
        [@@ocaml.warning "-8"]
      in
      let id = Task.id dep in
      let bindings = Run.runExn (Task.buildEnv task) in
      let f = function
        | "OK", value ->
          let expected =
            Fpath.(buildConfig.storePath / "i" / id / "ok")
            |> Fpath.to_string
            |> EsyLib.Path.normalizePathSlashes
          in
          Some (value = expected)
        | "OK_BY_NAME", value ->
          let expected =
            Fpath.(buildConfig.storePath / "i" / id / "ok-by-name")
            |> Fpath.to_string
            |> EsyLib.Path.normalizePathSlashes
          in
          Some (value = expected)
        | _ ->
          None
      in
      not (
        bindings
        |> Sandbox.Environment.Bindings.render buildConfig
        |> EsyLib.Environment.renderToList
        |> List.map f
        |> List.exists (function | Some false -> true | _ -> false)
      )
    )

let checkEnvExists ~name ~value task =
  let bindings =
    Sandbox.Environment.Bindings.render buildConfig (Run.runExn (Task.buildEnv task))
  in
  List.exists
    (function
      | n, v when name = n ->
        if v = value
        then true
        else false
      | _ -> false)
    (EsyLib.Environment.renderToList bindings)

  let%test "#{OCAMLPATH} depending on os" =
    let dep = Sandbox.Package.{
      dep with
      build = {
        dep.build with
        exportedEnv = [
          {
            Manifest.ExportedEnv.
            name = "OCAMLPATH";
            value = "#{'one' : 'two'}";
            exclusive = false;
            scope = Local;
          };
          {
            Manifest.ExportedEnv.
            name = "PATH";
            value = "#{'/bin' : '/usr/bin'}";
            exclusive = false;
            scope = Local;
          };
          {
            Manifest.ExportedEnv.
            name = "OCAMLLIB";
            value = "#{os == 'windows' ? ('lib' / 'ocaml') : 'lib'}";
            exclusive = false;
            scope = Local;
          };
        ];
      };
    } in
    let pkg = pkg in
    let dependencies = [Ok (Sandbox.Dependency.Dependency, dep)] in
    check ~platform:System.Platform.Linux (makeSandbox pkg dependencies) (fun task ->
      checkEnvExists ~name:"OCAMLPATH" ~value:"one:two" task
      && checkEnvExists ~name:"PATH" ~value:"/bin:/usr/bin" task
      && checkEnvExists ~name:"OCAMLLIB" ~value:"lib" task
    )
    &&
    check ~platform:System.Platform.Windows (makeSandbox pkg dependencies) (fun task ->
      checkEnvExists ~name:"OCAMLPATH" ~value:"one;two" task
      && checkEnvExists ~name:"PATH" ~value:"/bin;/usr/bin" task
      && checkEnvExists ~name:"OCAMLLIB" ~value:"lib/ocaml" task
    )

end
