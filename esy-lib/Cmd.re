/*
 * Tool and a reversed list of args.
 *
 * We store args reversed so we allow an efficient append.
 *
 * XXX: It is important we do List.rev at the boundaries so we don't get a
 * reversed argument order.
 */
[@deriving (ord, yojson)]
type t = (string, list(string));

let v = tool => (tool, []);

let ofPath = path => v(Path.show(path));

let p = Path.show;

let addArg = (arg, (tool, args)) => {
  let args = [arg, ...args];
  (tool, args);
};

let addArgs = (nargs, (tool, args)) => {
  let args = {
    let f = (args, arg) => [arg, ...args];
    List.fold_left(~f, ~init=args, nargs);
  };

  (tool, args);
};

let (%) = ((tool, args), arg) => {
  let args = [arg, ...args];
  (tool, args);
};

let getToolAndArgs = ((tool, args)) => {
  let args = List.rev(args);
  (tool, args);
};

let ofToolAndArgs = ((tool, args)) => {
  let args = List.rev(args);
  (tool, args);
};

let getToolAndLine = ((tool, args)) => {
  let args = List.rev(args);
  /* On Windows, we need the tool to be the empty string to use path resolution */
  /* More info here: http://ocsigen.org/lwt/3.2.1/api/Lwt_process */
  switch (System.Platform.host) {
  | Windows => ("", Array.of_list([tool, ...args]))
  | _ => (tool, Array.of_list([tool, ...args]))
  };
};

let getTool = ((tool, _args)) => tool;

let getArgs = ((_tool, args)) => List.rev(args);

let mapTool = (f, (tool, args)) => (f(tool), args);

let show = ((tool, args)) => {
  let tool = Filename.quote(tool);
  let args = List.rev_map(~f=Filename.quote, args);
  StringLabels.concat(~sep=" ", [tool, ...args]);
};

let pp = (ppf, (tool, args)) =>
  switch (args) {
  | [] => Fmt.(pf(ppf, "%s", tool))
  | args =>
    let args = List.rev(args);
    let line = List.map(~f=Filename.quote, [tool, ...args]);
    Fmt.(pf(ppf, "@[<h>%a@]", list(~sep=sp, string), line));
  };

let isExecutable = (stats: Unix.stats) => {
  let userExecute = 0b001000000;
  let groupExecute = 0b000001000;
  let othersExecute = 0b000000001;
  userExecute lor groupExecute lor othersExecute land stats.Unix.st_perm != 0;
};

/*
 * When running from some contexts, like the ChildProcess, only the system paths are provided.
 * However, on Windows, we also need to check the equivalent of the `bin` and `usr/bin` folders,
 * as shell commands are provided there (these paths get converted to their cygwin equivalents and checked).
 */
let getAdditionalResolvePaths = path =>
  switch (System.Platform.host) {
  | Windows => path @ ["/bin", "/usr/bin"]
  | _ => path
  };

let getPotentialExtensions =
  switch (System.Platform.host) {
  | Windows =>
    /* TODO(andreypopp): Consider using PATHEXT env variable here. */
    ["", ".exe", ".cmd"]
  | _ => [""]
  };

let checkIfExecutable = path =>
  Result.Syntax.(
    switch (System.Platform.host) {
    /* Windows has a different file policy model than Unix - matching with the Unix permissions won't work */
    /* In particular, the Unix.stat implementation emulates this on Windows by checking the extension for `exe`/`com`/`cmd`/`bat` */
    /* But in our case, since we're deferring to the Cygwin layer, it's possible to have executables that don't confirm to that rule */
    | Windows =>
      let* exists = Bos.OS.Path.exists(path);
      switch (exists) {
      | true => Ok(Some(path))
      | _ => Ok(None)
      };
    | _ =>
      let* stats = Bos.OS.Path.stat(path);
      switch (stats.Unix.st_kind, isExecutable(stats)) {
      | (Unix.S_REG, true) => Ok(Some(path))
      | _ => Ok(None)
      };
    }
  );

let checkIfCommandIsAvailable = fullPath => {
  let extensions = getPotentialExtensions;
  let evaluate = (prev, next) =>
    switch (prev) {
    | Ok(Some(x)) => Ok(Some(x))
    | _ =>
      let pathToTest = Fpath.to_string(fullPath) ++ next;
      let p = Fpath.v(pathToTest);
      checkIfExecutable(p);
    };

  List.fold_left(~f=evaluate, ~init=Ok(None), extensions);
};

let resolveCmd = (path, cmd) => {
  open Result.Syntax;
  let allPaths = getAdditionalResolvePaths(path);
  let find = p => {
    let p = Path.(v(p) / cmd);
    let p = EsyBash.normalizePathForWindows(p);
    checkIfCommandIsAvailable(p);
  };

  let rec resolve =
    fun
    | [] => Error(`Msg("unable to resolve command: " ++ cmd))
    | ["", ...xs] => resolve(xs)
    | [x, ...xs] =>
      switch (find(x)) {
      | Ok(Some(x)) => Ok(Path.show(x))
      | Ok(None)
      | Error(_) => resolve(xs)
      };

  switch (cmd.[0]) {
  | '.'
  | '/' => Ok(cmd)
  | _ =>
    let isSep = (
      fun
      | '/' => true
      | '\\' => true
      | _ => false
    );

    if (Astring.String.exists(isSep, cmd)) {
      return(cmd);
    } else {
      resolve(allPaths);
    };
  };
};

let resolveInvocation = (path, (tool, args)) => {
  open Result.Syntax;
  let* tool = resolveCmd(path, tool);
  return((tool, args));
};

let toBosCmd = cmd => {
  let (tool, args) = getToolAndArgs(cmd);
  Bos.Cmd.of_list([tool, ...args]);
};

let ofBosCmd = cmd =>
  switch (Bos.Cmd.to_list(cmd)) {
  | [] => Error(`Msg("empty command"))
  | [tool, ...args] => [@implicit_arity] Ok(tool, List.rev(args))
  };

let ofListExn =
  fun
  | [] => raise(Invalid_argument("empty command"))
  | [tool, ...args] => v(tool) |> addArgs(args);
