/**
 * This implements simple substitution syntax %name%.
 */
let re =
  Re.(
    compile(
      seq([
        char('%'),
        char('{'),
        group(rep1(alnum)),
        char('}'),
        char('%'),
      ]),
    )
  );

type env = string => option(string);

let renderExn = (env: env, path: string) => {
  let replace = g => {
    let name = Re.Group.get(g, 1);
    switch (env(name)) {
    | None => "%{" ++ name ++ "}%"
    | Some(value) => value
    };
  };
  Re.replace(~all=true, re, path, ~f=replace);
};

let render = (env: env, path: string) => Ok(renderExn(env, path));
