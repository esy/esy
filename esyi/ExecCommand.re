module Path = EsyLib.Path;
module Cmd = EsyLib.Cmd;

let withWorkingDir = (~dir, f) => {
  let dir = Path.toString(dir);
  let currDir = Unix.getcwd();
  Unix.chdir(dir);
  let result =
    try (f()) {
    | err =>
      Unix.chdir(currDir);
      raise(err);
    };
  Unix.chdir(currDir);
  result;
};

let execStringSync = (~cmd, ~onOut=?, ()) => {
  let chan = Unix.open_process_in(cmd);
  try (
    {
      let rec loop = () =>
        switch (Pervasives.input_line(chan)) {
        | exception End_of_file => []
        | line =>
          switch (onOut) {
          | None => ()
          | Some(fn) => fn(line)
          };
          [line, ...loop()];
        };
      let lines = loop();
      switch (Unix.close_process_in(chan)) {
      | WEXITED(0) => (lines, true)
      | WEXITED(_)
      | WSIGNALED(_)
      | WSTOPPED(_) => (lines, false)
      };
    }
  ) {
  | End_of_file => ([], false)
  };
};

/** TODO use lwt or something */
/**
 * Get the output of a command, in lines.
 */
let execSync = (~cmd, ~workingDir=?, ()) => {
  let f = () => {
    let cmd = Cmd.toString(cmd);
    execStringSync(~cmd, ());
  };
  switch (workingDir) {
  | Some(workingDir) => withWorkingDir(~dir=workingDir, f)
  | None => f()
  };
};

let execSyncOrFail = (~cmd, ~workingDir=?, ()) => {
  let msg = Printf.sprintf("error running %s", Cmd.toString(cmd));
  execSync(~cmd, ~workingDir?, ()) |> snd |> Files.expectSuccess(msg);
};
