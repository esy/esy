include Rresult;

let ok = Ok();

let join = rr =>
  switch rr {
  | Ok(Ok(v)) => Ok(v)
  | Ok(v) => v
  | Error(msg) => Error(msg)
  };

let map = f =>
  fun
  | Ok(v) => Ok(f(v))
  | Error(err) => Error(err);

let (>>) = (a, b) =>
  switch a {
  | Ok () => b()
  | Error(msg) => Error(msg)
  };

let listMap = (f, xs) => {
  let f = (prev, x) =>
    switch prev {
    | Ok(xs) =>
      switch (f(x)) {
      | Ok(x) => Ok([x, ...xs])
      | Error(err) => Error(err)
      }
    | error => error
    };
  xs |> List.fold_left(f, Ok([])) |> map(List.rev);
};

module Let_syntax = {
  let bind = (~f, v) =>
    switch v {
    | Ok(v) => f(v)
    | Error(e) => Error(e)
    };
  module Open_on_rhs = {
    let return = v => Ok(v);
  };
};
