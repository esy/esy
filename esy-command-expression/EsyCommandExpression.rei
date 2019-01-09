/**
 * Command expression language
 *
 * This is a small language which allows to define build commands which use
 * parameters from the build configuration.
 *
 * Constructs supported are
 *
 * - Variables:
 *    name
 *
 * - String literals:
 *    "value"
 *
 * - Colons:
 *    :
 *
 * - Path separators:
 *    /
 *
 * - Environment variables
 *    $NAME
 *
 * - Conditionals:
 *    cond ? then : else
 *
 * - Logical AND
 *    cond && cond2 ? then : else
 *
 * - Parens (for grouping)
 *    (A B)
 *
 * - Sequences (treated as concatenations):
 *    A B C
 *
 * Examples
 *
 * - #{"--" (@opam/lwt.installed ? "enable" : "disable") "-lwt"}
 *
 */;

module Value: {
  type t =
    | String(string)
    | Bool(bool);
  let equal: (t, t) => bool;
  let compare: (t, t) => int;
  let show: t => string;
  let pp: (Format.formatter, t) => unit;
};

let bool: bool => Value.t;
let string: string => Value.t;

type scope = ((option(string), string)) => option(Value.t);

/** Render command expression into a string given the [scope]. */

let render:
  (
    ~envVar: string => result(Value.t, string)=?,
    ~pathSep: string=?,
    ~colon: string=?,
    ~scope: scope,
    string
  ) =>
  result(string, string);
