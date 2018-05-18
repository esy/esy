type t = Bos.Cmd.t;

let ofList = Bos.Cmd.of_list;
let toList = Bos.Cmd.to_list;
let v = Bos.Cmd.v;
let p = Bos.Cmd.p;
let (%) = Bos.Cmd.(%);
let (%%) = Bos.Cmd.(%%);
let empty = Bos.Cmd.empty;

let isExecutable = (stats: Unix.stats) => {
  let userExecute = 0b001000000;
  let groupExecute = 0b000001000;
  let othersExecute = 0b000000001;
  userExecute lor groupExecute lor othersExecute land stats.Unix.st_perm != 0;
};

let resolveCmd = (path, cmd) => {
  module Let_syntax = Result.Let_syntax;
  let find = p => {
    let p = Path.(v(p) / cmd);
    let%bind stats = Bos.OS.Path.stat(p);
    switch (stats.Unix.st_kind, isExecutable(stats)) {
    | (Unix.S_REG, true) => Ok(Some(p))
    | _ => Ok(None)
    };
  };
  let rec resolve =
    fun
    | [] => Error(`Msg("unable to resolve command: " ++ cmd))
    | ["", ...xs] => resolve(xs)
    | [x, ...xs] =>
      switch (find(x)) {
      | Ok(Some(x)) => Ok(Path.to_string(x))
      | Ok(None)
      | Error(_) => resolve(xs)
      };
  switch (cmd.[0]) {
  | '.'
  | '/' => Ok(cmd)
  | _ => resolve(path)
  };
};

let resolveInvocation = (path, cmd) => {
  module Let_syntax = Result.Let_syntax;
  let cmd = Bos.Cmd.to_list(cmd);
  switch (cmd) {
  | [] => Error(`Msg("empty command"))
  | [cmd, ...args] =>
    let%bind cmd = resolveCmd(path, cmd);
    Ok(Bos.Cmd.of_list([cmd, ...args]));
  };
};
