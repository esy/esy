open TestFramework;

// module EsyBash = EsyLib.EsyBash;
module Path = EsyLib.Path;
module Option = EsyLib.Option;
module Result = EsyLib.Result;
module Cmd = Bos.Cmd;
module OS = Bos.OS;
module Dir = OS.Dir;
module File = OS.File;
module BPath = OS.Path;
module Env = OS.Env;

open Shared;

type sandboxActions = {
  remove: unit => result(unit),
  esy: string => result(string),
  fixtures: list(Fixture.t) => result(unit),
  defineNpmPackage: NpmPublish.t => action,
  defineNpmPackages: list(NpmPublish.t) => action,
  defineOpamPackage: OpamMock.spec => action,
  defineOpamPackages: list(OpamMock.spec) => action,
};
/* Rely doesn't have afterAll method, need to think of cleanup method **/
let sandboxes: ref(list(string)) = ref([]);
let addSandbox = (path: string) => {
  sandboxes := [path, ...sandboxes^];
};

let skipSuiteOnWindows = (~blockingIssue="Needs investigation", ()) =>
  if (isWindows) {
    describeOnly("", ({testOnly, _}) =>
      testOnly("does not work on windows", _ =>
        Esy_logs.debug(m =>
          m("[SKIP] Needs to be unblocked: %s", blockingIssue)
        )
      )
    );
  };

let createSandbox = (~fixture=[], npmMock) => {
  open Result.Syntax;
  let numb = Random.int(20000);
  let* tmp = getTempDir("esy-" ++ string_of_int(numb));
  /* Save it, so it can be cleaned up later */
  // addSandbox(Path.show(tmp));
  /* Paths */
  let projectPath = Path.addSeg(tmp, "project");
  let binPath = Path.addSeg(tmp, "bin");
  let npmPrefixPath = Path.addSeg(tmp, "npm");
  let esyPrefixPath = Path.addSeg(tmp, "esy");
  let esyExePath = Path.addSeg(binPath, exe("esy"));

  // Setup directores
  // Use underscore because it returns Ok(bool)
  let* _ = Dir.create(tmp);
  let* _ = Dir.create(binPath);
  let* _ = Dir.create(projectPath);
  let* _ = Dir.create(npmPrefixPath);
  let* () = BPath.symlink(~target=esyLocalPath, esyExePath);
  /* Initialize mock handlers */
  let* () = Fixture.layoutMany(projectPath, fixture);
  let* opamMockR = OpamMock.initialize();
  // Type issues when accesing fields otherwise
  let opamMock: OpamMock.registry = opamMockR;

  let* currentEnv = Env.current();
  let esyEnv =
    Astring.String.Map.(
      currentEnv
      |> add("ESY__PREFIX", Path.show(esyPrefixPath))
      |> add("ESY__PROJECT", Path.show(projectPath))
      |> add("NPM_CONFIG_REGISTRY", npmMock)
      |> add(
           "ESYI__OPAM_REPOSITORY_LOCAL",
           Path.show(opamMock.registryPath),
         )
      |> add("ESYI__OPAM_OVERRIDE_LOCAL", Path.show(opamMock.overridePath))
      |> remove("ESY__ROOT_PACKAGE_CONFIG_PATH")
    );
  let esyCmd = Cmd.v(Path.show(esyExePath));

  let remove = () => {
    let* _ = Dir.delete(~recurse=true, tmp);
    let* _ = opamMock.remove();
    return();
  };
  let esy = cmd => {
    let revert = changeCwd(Path.show(projectPath));
    let cmdList = String.split_on_char(' ', cmd);
    let program = Cmd.(esyCmd %% of_list(cmdList));
    let* result = OS.Cmd.(run_out(~env=esyEnv, program) |> to_string);
    revert();
    return(result);
  };

  let fixtures = entries => {
    Fixture.layoutMany(projectPath, entries);
  };

  let defineNpmPackage = (package, ()) =>
    NpmPublish.publish(package, npmMock);
  let defineNpmPackages = (packages, ()) => {
    let* _ = Result.List.map(~f=p => defineNpmPackage(p, ()), packages);
    return();
  };
  let defineOpamPackage = (package, ()) =>
    OpamMock.defineOpamPackage(opamMock, package);
  let defineOpamPackages = (packages, ()) => {
    let* _ = Result.List.map(~f=p => defineOpamPackage(p, ()), packages);
    return();
  };

  let sandboxActions: sandboxActions = {
    remove,
    esy,
    fixtures,
    defineNpmPackage,
    defineNpmPackages,
    defineOpamPackage,
    defineOpamPackages,
  };

  Result.return(sandboxActions);
};
