/**
 * This implements simple substitution syntax %name%.
 */
let re = Re.(compile(seq([char('%'), group(rep1(alnum)), char('%')])));

type env = string => option(string);

exception UnknownPathVariable(string);

let renderExn = (env: env, path: string) => {
  let replace = g => {
    let name = Re.Group.get(g, 1);
    switch (env(name)) {
    | None => raise(UnknownPathVariable(name))
    | Some(value) => value
    };
  };
  Re.replace(~all=true, re, path, ~f=replace);
};

let render = (env: env, path: string) =>
  try (Ok(renderExn(env, path))) {
  | UnknownPathVariable(name) =>
    let msg =
      Printf.sprintf(
        "unable to render path: '%s' because of unknown variable %s",
        path,
        name,
      );
    Error(`Msg(msg));
  };