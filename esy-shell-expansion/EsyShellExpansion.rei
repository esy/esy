/**

  Shell parameter expansion.

  This is a limited implementation of shell parameter expansion as found imn
  popular Unix shells like sh, bash and so on.

  The only supported constructs are:

    - substitution: `$VALUE` or `${VALUE}`
    - substitution with default: `${VALUE:-DEFAULT}`

 */;

type scope = string => option(string);

/** Render string by expanding all shell parameters found. */

let render:
  (~fallback: option(string)=?, ~scope: scope, string) =>
  result(string, string);
