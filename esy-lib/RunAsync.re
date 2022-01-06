type t('a) = Lwt.t(Run.t('a));

let return = v => Lwt.return(Ok(v));

let error = msg => Lwt.return(Run.error(msg));

let errorf = fmt => {
  let kerr = _ => Lwt.return(Run.error(Format.flush_str_formatter()));
  Format.kfprintf(kerr, Format.str_formatter, fmt);
};

let context = (v, msg) => {
  let%lwt v = v;
  Lwt.return(Run.context(v, msg));
};

let contextf = (v, fmt) => {
  let kerr = _ => context(v, Format.flush_str_formatter());
  Format.kfprintf(kerr, Format.str_formatter, fmt);
};

let withContextOfLog = (~header=?, content, v) => {
  let%lwt v = v;
  Lwt.return(Run.withContextOfLog(~header?, content, v));
};

let map = (~f, v) => {
  let waitForPromise =
    fun
    | Ok(v) => Lwt.return(Ok(f(v)))
    | Error(err) => Lwt.return(Error(err));

  Lwt.bind(v, waitForPromise);
};

let bind = (~f, v) => {
  let waitForPromise =
    fun
    | Ok(v) => f(v)
    | Error(err) => Lwt.return(Error(err));

  Lwt.bind(v, waitForPromise);
};

let both = (a, b) => {
  let%lwt a = a
  and b = b;
  Lwt.return(
    switch (a, b) {
    | (Ok(a), Ok(b)) => [@implicit_arity] Ok(a, b)
    | (Ok(_), Error(err)) => Error(err)
    | (Error(err), Ok(_)) => Error(err)
    | (Error(err), Error(_)) => Error(err)
    },
  );
};

let ofRun = Lwt.return;
let ofStringError = r => ofRun(Run.ofStringError(r));
let ofBosError = r => ofRun(Run.ofBosError(r));

module Syntax = {
  let return = return;
  let error = error;
  let errorf = errorf;
  let ( let* ) = (v, f) => bind(~f, v);

  module Let_syntax = {
    let map = map;
    let bind = bind;
    let both = both;
  };
};

let ofOption = (~err=?, v) =>
  switch (v) {
  | Some(v) => return(v)
  | None =>
    let err =
      switch (err) {
      | Some(err) => err
      | None => "not found"
      };
    error(err);
  };

let runExn = (~err=?, v) => {
  let v = Lwt_main.run(v);
  Run.runExn(~err?, v);
};

let cleanup = (comp, handler) => {
  let res =
    switch%lwt (comp) {
    | Ok(res) => return(res)
    | Error(_) as err =>
      let%lwt () = handler();
      Lwt.return(err);
    };

  try%lwt(res) {
  | err =>
    let%lwt () = handler();
    raise(err);
  };
};

module List = {
  let foldLeft = (~f: ('a, 'b) => t('a), ~init: 'a, xs: list('b)) => {
    let rec fold = (acc, xs) =>
      switch%lwt (acc) {
      | Error(err) => Lwt.return(Error(err))
      | Ok(acc) =>
        switch (xs) {
        | [] => return(acc)
        | [x, ...xs] => fold(f(acc, x), xs)
        }
      };

    fold(return(init), xs);
  };

  let joinAll = xs => {
    let rec _joinAll = (xs, res) =>
      switch (xs) {
      | [] => return(List.rev(res))
      | [x, ...xs] =>
        let f = v => _joinAll(xs, [v, ...res]);
        bind(~f, x);
      };

    _joinAll(xs, []);
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

  let limitWithConccurrency = (concurrency, f) =>
    switch (concurrency) {
    | None => f
    | Some(concurrency) =>
      let queue = LwtTaskQueue.create(~concurrency, ());
      (x => LwtTaskQueue.submit(queue, () => f(x)));
    };

  let mapAndWait = (~concurrency=?, ~f, xs) =>
    waitAll(List.map(~f=limitWithConccurrency(concurrency, f), xs));

  let map = (~concurrency=?, ~f, xs) =>
    joinAll(List.map(~f=limitWithConccurrency(concurrency, f), xs));

  let filter = (~concurrency=?, ~f, xs) => {
    open Syntax;
    let f = x =>
      if%bind (f(x)) {
        return(Some(x));
      } else {
        return(None);
      };
    let f = limitWithConccurrency(concurrency, f);
    let* xs = joinAll(List.map(~f, xs));
    return(List.filterNone(xs));
  };

  let mapAndJoin = map;

  let rec processSeq = (~f) =>
    Syntax.(
      fun
      | [] => return()
      | [x, ...xs] => {
          let* () = f(x);
          processSeq(~f, xs);
        }
    );
};
