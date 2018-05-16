
/** TODO use lwt or something */

/**
 * Get the output of a command, in lines.
 */
let execSync = (~cmd, ~onOut=?, ()) => {
  let chan = Unix.open_process_in(cmd);
  try {
    let rec loop = () =>
      switch (Pervasives.input_line(chan)) {
      | exception End_of_file => []
      | line => {
        switch onOut {
        | None => ()
        | Some(fn) => fn(line)
        };
        [line, ...loop()]
      }
      };
    let lines = loop();
    switch (Unix.close_process_in(chan)) {
    | WEXITED(0) => (lines, true)
    | WEXITED(_)
    | WSIGNALED(_)
    | WSTOPPED(_) => (lines, false)
    }
  } {
  | End_of_file => ([], false)
  }
};
