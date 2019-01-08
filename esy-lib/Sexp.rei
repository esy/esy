/*

  An s-expression builder.

 */

type t = list(item)
and item =
  | Value(value)
  | Comment(string)
and value =
  | S(string)
  | N(float)
  | I(string)
  | L(list(value));

/** Render an s-expression to a string */
let render: t => string;
