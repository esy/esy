/**
 * Commands.
 *
 * Command is a tool and a list of arguments.
 */;

type t;

let to_yojson: Json.encoder(t);
let of_yojson: Json.decoder(t);

/** Produce a command supplying a tool. */

let v: string => t;

let ofPath: Path.t => t;

/** Add a new argument to the command. */

let (%): (t, string) => t;

/** Convert path to a string suitable to use with (%). */

let p: Path.t => string;

/**
 * Add a new argument to the command.
 *
 * Same as (%) but with a flipped argument order.
 * Added for convenience usage with (|>).
 */

let addArg: (string, t) => t;

/**
 * Add a list of arguments to the command.
 *
 * it is convenient to use with (|>).
 */

let addArgs: (list(string), t) => t;

let getToolAndArgs: t => (string, list(string));
let ofToolAndArgs: ((string, list(string))) => t;

/**
 * Get a tuple of a tool and a list of argv suitable to be passed into
 * Lwt_process or Unix family of functions.
 */

let getToolAndLine: t => (string, array(string));

let getTool: t => string;
let getArgs: t => list(string);

let mapTool: (string => string, t) => t;

include S.PRINTABLE with type t := t;
include S.COMPARABLE with type t := t;

/** TODO: remove away, use resolveInvocation instead */

let resolveInvocation: (list(string), t) => result(t, [> | `Msg(string)]);

/** TODO: remove away, use resolveInvocation instead */

let resolveCmd:
  (list(string), string) => result(string, [> | `Msg(string)]);

/**
 * Interop with Bos.Cmd.t
 *  TODO: get rid of that
 */

let toBosCmd: t => Bos.Cmd.t;
let ofBosCmd: Bos.Cmd.t => result(t, [> | `Msg(string)]);

let ofListExn: list(string) => t;
