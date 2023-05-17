/**
 * Computation with structured error reporting.
 */

type t('a) = result('a, error)
and error = (string, context)
and context = list(contextItem)
and contextItem =
  | Line(string)
  | LogOutput((string, string));

let ppContextItem = fmt =>
  fun
  | Line(line) => Fmt.pf(fmt, "@[<h>%s@]", line)
  | [@implicit_arity] LogOutput(filename, out) =>
    Fmt.pf(fmt, "@[<h 2>%s@\n%a@]", filename, Fmt.text, out);

let ppContext = (fmt, context) =>
  Fmt.(list(~sep=any("@\n"), ppContextItem))(fmt, List.rev(context));

let ppError = (fmt, (msg, context)) =>
  Fmt.pf(
    fmt,
    "@[<v 2>@[<h>error: %a@]@\n%a@]",
    Fmt.text,
    msg,
    ppContext,
    context,
  );

let return = v => Ok(v);

let error = msg => [@implicit_arity] Error(msg, []);

let errorf = fmt => {
  let kerr = _ => [@implicit_arity] Error(Format.flush_str_formatter(), []);
  Format.kfprintf(kerr, Format.str_formatter, fmt);
};

let context = (line, v) =>
  switch (v) {
  | Ok(v) => Ok(v)
  | Error((msg, context)) => Error((msg, [Line(line), ...context]))
  };

let contextf = (v, fmt) => {
  let kerr = _ => context(Format.flush_str_formatter(), v);
  Format.kfprintf(kerr, Format.str_formatter, fmt);
};

let bind = (~f, v) =>
  switch (v) {
  | Ok(v) => f(v)
  | Error(err) => Error(err)
  };

let map = (~f, v) =>
  switch (v) {
  | Ok(v) => Ok(f(v))
  | Error(err) => Error(err)
  };

let withContextOfLog = (~header="Log output:", content, v) =>
  switch (v) {
  | Ok(v) => Ok(v)
  | [@implicit_arity] Error(msg, context) =>
    let item = [@implicit_arity] LogOutput(header, content);
    [@implicit_arity] Error(msg, [item, ...context]);
  };

let formatError = error => Format.asprintf("%a", ppError, error);

let ofStringError = v =>
  switch (v) {
  | Ok(v) => Ok(v)
  | Error(line) => [@implicit_arity] Error(line, [])
  };

let ofBosError = v =>
  switch (v) {
  | Ok(v) => Ok(v)
  | Error(`Msg(line)) => [@implicit_arity] Error(line, [])
  | Error(`CommandError(cmd, status)) =>
    let line =
      Format.asprintf(
        "command %a exited with status %a",
        Bos.Cmd.pp,
        cmd,
        Bos.OS.Cmd.pp_status,
        status,
      );

    [@implicit_arity] Error(line, []);
  };

let ofOption = (~err=?) =>
  fun
  | Some(v) => return(v)
  | None => {
      let err =
        switch (err) {
        | Some(err) => err
        | None => "not found"
        };
      error(err);
    };

let toResult =
  fun
  | Ok(v) => Ok(v)
  | Error(err) => Error(formatError(err));

let runExn = (~err=?) =>
  fun
  | Ok(v) => v
  | [@implicit_arity] Error(msg, ctx) => {
      let msg =
        switch (err) {
        | Some(err) => err ++ ": " ++ msg
        | None => msg
        };

      failwith(formatError((msg, ctx)));
    };

module Syntax = {
  let return = return;
  let error = error;
  let errorf = errorf;
  let ( let* ) = (v, f) => bind(~f, v);

  module Let_syntax = {
    let bind = bind;
    let map = map;
  };
};

module List = {
  let foldLeft = (~f, ~init, xs) => {
    let rec fold = (acc, xs) =>
      switch (acc, xs) {
      | (Error(err), _) => Error(err)
      | (Ok(acc), []) => Ok(acc)
      | (Ok(acc), [x, ...xs]) => fold(f(acc, x), xs)
      };

    fold(Ok(init), xs);
  };

  let waitAll = xs => {
    let rec _waitAll = xs =>
      switch (xs) {
      | [] => return()
      | [x, ...xs] =>
        let f = () => _waitAll(xs);
        bind(~f, x);
      };

    _waitAll(xs);
  };

  let mapAndWait = (~f, xs) => waitAll(List.map(~f, xs));
};
