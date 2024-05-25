/**
 * This module prrovides info about the current system we are running on.
 *
 * It does some I/O to query the system and if it fails then esy isn't operable
 * on the system at all.
 */;

/** Platform */

module Platform: {
  type t =
    | Darwin
    | Linux
    | Cygwin
    | Windows
    | Unix
    | Unknown;

  /** Platform we are currently running on */

  let host: t;

  let isWindows: bool;

  include S.JSONABLE with type t := t;
  include S.PRINTABLE with type t := t;
  include S.COMPARABLE with type t := t;
};

module Arch: {
  type t =
    | X86_32
    | X86_64
    | Ppc32
    | Ppc64
    | Arm32
    | Arm64
    | Unknown;

  /** Arch we are currently running on */

  let host: t;

  include S.JSONABLE with type t := t;
  include S.PRINTABLE with type t := t;
  include S.COMPARABLE with type t := t;
};

let supportsLongPaths: unit => bool;

let ensureMinimumFileDescriptors: unit => unit;

let moveFile: (string, string) => unit;

let getumask: unit => int;

module Environment: {
  /** Environment variable separator which is used for $PATH and etc */

  let sep: (~platform: Platform.t=?, ~name: string=?, unit) => string;

  /** Split environment variable value in a cross platform way. */

  let split:
    (~platform: Platform.t=?, ~name: string=?, string) => list(string);

  /** Join environment variable value in a cross plartform way. */

  let join:
    (~platform: Platform.t=?, ~name: string=?, list(string)) => string;

  /** Current environment. */

  let current: StringMap.t(string);

  /** Value of $PATH environment variable. */

  let path: list(string);

  /** Helper method to normalize CRLF (Windows) text-context to LF (POSIX) */

  let normalizeNewLines: string => string;
};
