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

/**
 * Get the output of a command, in lines.
 */
let execSync = (~cmd, ~workingDir=?, ~onOut=?, ()) => {
  Logs.debug(m => m("exec: %s", Cmd.toString(cmd)));
  let f = () => {
    let cmd = Cmd.toString(cmd);
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
  switch (workingDir) {
  | Some(workingDir) => withWorkingDir(~dir=workingDir, f)
  | None => f()
  };
};

let execSyncOrFail = (~err=?, ~cmd, ~workingDir=?, ()) => {
  let err =
    switch (err) {
    | Some(err) => err
    | None => Printf.sprintf("Unable to run command: %s", Cmd.toString(cmd))
    };
  execSync(~cmd, ~workingDir?, ()) |> snd |> Files.expectSuccess(err);
};
