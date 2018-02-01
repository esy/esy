module StringMap = Map.Make(String);

module StringSet = Set.Make(String);

module PathSet = Set.Make(Path);

module ConfigPath = Config.ConfigPath;

let find = (~name, task: BuildTask.t) => {
  let f = (task: BuildTask.t) => task.pkg.name == name;
  BuildTask.DependencyGraph.find(~f, task);
};

let getOcamlfind = (~cfg: Config.t, task: BuildTask.t) =>
  RunAsync.Syntax.(
    switch (find(~name="@opam/ocamlfind", task)) {
    | None =>
      error(
        "We couldn't find ocamlfind, consider adding it to your devDependencies"
      )
    | Some(ocamlfindTask) =>
      let ocamlfindBin =
        ConfigPath.(
          ocamlfindTask.installPath / "bin" / "ocamlfind" |> toPath(cfg)
        );
      let%bind built = Fs.exists(ocamlfindBin);
      if (built) {
        return(Path.to_string(ocamlfindBin));
      } else {
        error("No ocamlfind binary was found, build your project first");
      };
    }
  );

let getPackageLibraries =
    (~cfg: Config.t, ~ocamlfind: string, ~builtIns=?, ~task=?, ()) => {
  open RunAsync.Syntax;
  let ocamlpath =
    switch task {
    | Some((task: BuildTask.t)) =>
      ConfigPath.(task.installPath / "lib" |> toPath(cfg)) |> Path.to_string
    | None => ""
    };
  let env =
    `CustomEnv(Astring.String.Map.(empty |> add("OCAMLPATH", ocamlpath)));
  let cmd = Cmd.ofList([ocamlfind, "list"]);
  let%bind out = ChildProcess.runOut(~env, cmd);
  let libs =
    String.split_on_char('\n', out)
    |> List.map(line =>
         switch (String.index(line, ' ')) {
         | idx => Some(String.sub(line, 0, idx))
         | exception Not_found => None
         }
       )
    |> Std.List.filterNone
    |> List.rev;
  switch builtIns {
  | Some(discard) =>
    let diff = List.filter(lib => ! List.mem(lib, discard), libs);
    return(diff);
  | None => return(libs)
  };
};

let formatPackageInfo = (~built: bool, task: BuildTask.t) => {
  open RunAsync.Syntax;
  let pkg = task.pkg;
  let version = Chalk.grey("@" ++ pkg.version);
  let status =
    switch (pkg.sourceType, built) {
    | (Package.SourceType.Immutable, true) => Chalk.green("[built]")
    | (Package.SourceType.Immutable, false)
    | (_, _) => Chalk.blue("[build pending]")
    };
  let line = Printf.sprintf("%s%s %s", pkg.name, version, status);
  return(line);
};