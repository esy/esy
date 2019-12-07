module Path = EsyLib.Path;
module Env = Bos.OS.Env;

module String = Astring.String;
module StringMap = String.Map;

/* ATM we use custom config to avoid use of auth module */
let verdaccioDir = Shared.makePath(~from=Shared.testDir, "./verdaccio");
let verdaccioStorage = Shared.makePath(~from=verdaccioDir, "./storage");
let verdaccioCfg = Shared.makePath(~from=verdaccioDir, "./config.yml");
/*
  Needs to be started from executable
  Otherwise, we might get problems with ports being left open
 */
let verdaccioExe =
  Shared.makePath(~from=verdaccioDir, "./node_modules/.bin/verdaccio");

/*
  Need to remove any _esy variables from PATH,
  otherwise pnp will be enforced
  Just use exn here instead of dealing with result
  As it's only done once
 */
let cleanPath = {
  let env = Env.current() |> Shared.rExn;
  let path = StringMap.get("PATH", env);
  let parts = String.cuts(~sep=":", path);
  let path =
    List.fold_left(
      (acc, item) =>
        if (Shared.contains(item, "esy")) {
          acc;
        } else {
          acc ++ item ++ ":";
        },
      "",
      parts,
    );
  /* Removes last ':' char */
  String.with_range(~first=0, ~len=String.length(path) - 1, path);
};

let cleanPathEnv = {
  let env = Env.current() |> Shared.rExn;
  let env = StringMap.add("PATH", cleanPath, env);

  let add_var = (name, value, acc) => [name ++ "=" ++ value, ...acc];
  Array.of_list(String.Map.fold(add_var, env, []));
};
/* Spawn long running process */
/* Check whether environment should be cleared */
/* Bos.OS, doesnt document create_process, but they do have it */
let runCmd = (cmd, args, cwd) => {
  open Unix;
  let (inRead, inWrite) = pipe();
  let (outRead, outWrite) = pipe();
  let (errRead, errWrite) = pipe();
  /* There seems to be issues with argument joining in create_process*/
  let args = ["", ...args];
  let revert = Shared.changeCwd(cwd);

  let pid =
    create_process_env(
      cmd,
      Array.of_list(args),
      cleanPathEnv,
      outRead,
      inWrite,
      errWrite,
    );
  revert();
  let inc = in_channel_of_descr(inRead);
  let outc = out_channel_of_descr(outWrite);
  let errc = in_channel_of_descr(errRead);
  (inc, outc, errc, pid);
};

let stopCmd = ((inc, outc, errc, pid)) => {
  open Unix;
  // Soft SIGTERM
  let () = kill(pid, 9);
  close_out(outc);
  close_in(inc);
  close_in(errc);
  // Wait till it's killed
  waitpid([WUNTRACED], pid) |> ignore;
};

let clearStorage = () =>
  switch (
    Bos.OS.Dir.delete(~must_exist=true, ~recurse=true, verdaccioStorage)
  ) {
  | Ok(_) => ()
  | Error(`Msg(error)) => failwith(error)
  };

let waitTillStarted = channel => {
  let rec loop = () => {
    let line =
      try(Some(input_line(channel))) {
      | End_of_file => None
      };
    switch (line) {
    | Some(line) => Shared.contains(line, "http address") ? () : loop()
    | None => ()
    };
  };
  loop();
};

let url = "http://localhost:4873";
let runWith = run => {
  let (inc, outc, errc, pid) =
    runCmd(
      Path.show(verdaccioExe),
      ["--config", Path.show(verdaccioCfg)],
      Path.show(verdaccioDir),
    );
  waitTillStarted(inc);

  let result = run(url);

  stopCmd((inc, outc, errc, pid));
  clearStorage();
  /*
    Not sure if this is the best place for that
    Is required for the error not to be swallowed
   */
  switch (result) {
  | Error(`Msg(m)) => failwith(m)
  | Ok(_) => ()
  };
};
