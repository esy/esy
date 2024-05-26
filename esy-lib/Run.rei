/**
 * A computation which might result in an error.
 */

type t('v) = result('v, error)
and error = (string, context)
and context = list(contextItem)
and contextItem =
  | Line(string)
  | LogOutput((string, string));

/**
 * Failied computation with an error specified by a message.
 */

let return: 'v => t('v);

/**
 * Failied computation with an error specified by a message.
 */

let error: string => t('v);

/**
 * Same with [error] but defined with a formatted string.
 */

let errorf: format4('a, Format.formatter, unit, t('v)) => 'a;

/**
 * Wrap computation with a context which will be reported in case of error
 */

let context: (string, t('v)) => t('v);

/**
 * Same as [context] but defined with a formatter.
 */

let contextf: (t('v), format4('a, Format.formatter, unit, t('v))) => 'a;

/**
 * Wrap computation with a context which will be reported in case of error
 */

let withContextOfLog: (~header: string=?, string, t('a)) => t('a);

/**
 * Format error.
 */

let formatError: error => string;

let ppError: Fmt.t(error);

/**
 * Run computation and raise an exception in case of failure.
 */

let runExn: (~err: string=?, t('a)) => 'a;

let ofStringError: result('a, string) => t('a);

let ofBosError:
  result(
    'a,
    [< | `Msg(string) | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status)],
  ) =>
  t('a);

let ofOption: (~err: string=?, option('a)) => t('a);

let toResult: t('a) => result('a, string);

/**
 * Convenience module which is designed to be openned locally with the
 * code which heavily relies on Run.t.
 *
 * This also brings monadic let operators and Let_syntax module into scope
 * and thus compatible with ppx_let.
 *
 * Example
 *
 *    let open Run.Syntax in
 *    let%bind v = getNumber ... in
 *    if v > 10
 *    then return (v + 1)
 *    else error "Less than 10"
 *
 */

module Syntax: {
  let return: 'a => t('a);
  let error: string => t('a);
  let errorf: format4('a, Format.formatter, unit, t('v)) => 'a;
  let ( let* ): (t('a), 'a => t('b)) => t('b);

  module Let_syntax: {
    let bind: (~f: 'a => t('b), t('a)) => t('b);
    let map: (~f: 'a => 'b, t('a)) => t('b);
  };
};

module List: {
  let foldLeft: (~f: ('a, 'b) => t('a), ~init: 'a, list('b)) => t('a);

  let waitAll: list(t(unit)) => t(unit);
  let mapAndWait: (~f: 'a => t(unit), list('a)) => t(unit);
};
