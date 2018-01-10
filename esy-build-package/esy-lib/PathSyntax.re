/**
 * This implements simple substitution syntax %name%.
 */
let re = Re.(compile(seq([char('%'), group(rep1(alnum)), char('%')])));

type env = string => option(string);

let render = (env: env, path: string) => {
  open Result;
  let replace = g => {
    let name = Re.Group.get(g, 1);
    switch (env(name)) {
    | None => raise(Not_found)
    | Some(value) => value
    };
  };
  try (Ok(Re.replace(~all=true, re, path, ~f=replace))) {
  | Not_found =>
    let msg = Printf.sprintf("unable to render path: %s", path);
    Error(`Msg(msg));
  };
};
