/**
 * An async computation which might result in an error.
 */;

type t('a) = Lwt.t(Run.t('a));

/**
 * Computation which results in a value.
 */

let return: 'a => t('a);

/**
 * Computation which results in an error.
 */

let error: string => t('a);

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
 * Run computation and throw an exception in case of a failure.
 *
 * Optional [err] will be used as error message.
 */

let runExn: (~err: string=?, t('a)) => 'a;

/**
 * Convert [Run.t] into [t].
 */

let ofRun: Run.t('a) => t('a);

/**
 * Convert [Lwt.t] into [t].
 */

let ofLwt: Lwt.t('a) => t('a);

/**
 * Convert an Rresult into [t]
 */

let ofStringError: result('a, string) => t('a);

let ofBosError:
  result(
    'a,
    [< | `Msg(string) | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status)],
  ) =>
  t('a);

let try_: (~catch: Run.error => t('a), t('a)) => t('a);

/**
 * Convert [option] into [t].
 *
 * [Some] will represent success and [None] a failure.
 *
 * An optional [err] will be used as an error message in case of failure.
 */

let ofOption: (~err: string=?, option('a)) => t('a);

/**
 * Convenience module which is designed to be openned locally with the
 * code which heavily relies on RunAsync.t.
 *
 * This also brings monadic let operators and Let_syntax module into scope
 * and thus compatible with ppx_let.
 *
 * Example
 *
 *    let open RunAsync.Syntax in
 *    let%bind v = fetchNumber ... in
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
    let both: (t('a), t('b)) => t(('a, 'b));
  };
};

/**
 * Work with lists of computations.
 */

module List: {
  let foldLeft: (~f: ('a, 'b) => t('a), ~init: 'a, list('b)) => t('a);

  let filter:
    (~concurrency: int=?, ~f: 'a => t(bool), list('a)) => t(list('a));

  let map: (~concurrency: int=?, ~f: 'a => t('b), list('a)) => t(list('b));

  let mapAndJoin:
    (~concurrency: int=?, ~f: 'a => t('b), list('a)) => t(list('b));

  let mapAndWait:
    (~concurrency: int=?, ~f: 'a => t(unit), list('a)) => t(unit);

  let waitAll: list(t(unit)) => t(unit);
  let joinAll: list(t('a)) => t(list('a));
  let processSeq: (~f: 'a => t(unit), list('a)) => t(unit);
};
