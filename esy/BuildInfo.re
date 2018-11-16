/**
 * Information about the task.
 */

[@deriving yojson]
type t = {
  timeSpent: float,
  sourceModTime: option(float),
};

let toFile = (path: Path.t, info: t) =>
  Fs.writeJsonFile(~json=to_yojson(info), path);

let ofFile = (path: EsyLib.Path.t) => {
  open RunAsync.Syntax;
  if%bind (Fs.exists(path)) {
    let%bind json = Fs.readJsonFile(path);
    switch (of_yojson(json)) {
    | Ok(v) => return(Some(v))
    | Error(_err) => return(None)
    };
  } else {
    return(None);
  };
};
