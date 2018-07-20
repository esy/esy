type env = string => option(string);

/** Render string using env. */
let render : (env, string) => result(string, [> `Msg(string) ])

exception UnknownPathVariable(string);

/** Same as render but raises UnknownPathVariable on unknown variable. */
let renderExn : (env, string) => string;
