/*

   Special substitution syntax %name%.

   This is used to parametrize tasks with build store locations.

 */

type env = string => option(string);

/** Render string using env. */
let render: (env, string) => result(string, string);

/** Same as render but raises UnknownPathVariable on unknown variable. */
let renderExn: (env, string) => string;
