let return = v => Some(v);

let orDefault = (~default) =>
  fun
  | None => default
  | Some(v) => v;

let orOther = (~other) =>
  fun
  | None => other
  | Some(v) => Some(v);

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

let isSome =
  fun
  | Some(_) => true
  | _ => false;

module Syntax = {
  let return = v => Some(v);
  let ( let* ) = (v, f) => bind(~f, v);
  module Let_syntax = {
    let bind = bind;
    let map = map;
  };
};
