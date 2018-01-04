let orDefault = default =>
  fun
  | None => default
  | Some(v) => v;

let map = (~f) =>
  fun
  | Some(v) => Some(f(v))
  | None => None;

let bind = (~f) =>
  fun
  | Some(v) => f(v)
  | None => None;

let isNone =
  fun
  | None => true
  | _ => false;
