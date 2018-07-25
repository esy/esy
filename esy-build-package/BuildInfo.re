/**
 * Information about the task.
 */
module Result = EsyLib.Result;
open Run;

[@deriving yojson]
type t = {
  timeSpent: float,
  sourceModTime: option(float),
};

let toFile = (path: EsyLib.Path.t, info: t) => {
  let data = Yojson.Safe.pretty_to_string(to_yojson(info));
  write(~data, path);
};

let ofFile = (path: EsyLib.Path.t) =>
  if%bind (exists(path)) {
    let%bind data = read(path);
    let json = Yojson.Safe.from_string(data);
    switch (of_yojson(json)) {
    | Ok(v) => Ok(Some(v))
    | Error(_err) => Ok(None)
    };
  } else {
    Ok(None);
  };
