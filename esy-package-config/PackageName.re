type t = string;

let withoutScope = name =>
  switch (Astring.String.cut(~sep="/", name)) {
  | None => name
  | Some((_scope, name)) => name
  };
