/**
 * Information about the task.
 */

[@deriving yojson]
type t = {
  idInfo: BuildId.Repr.t,
  timeSpent: float,
  sourceModTime: option(float),
};

let toFile = (path: Path.t, info: t) => {
  let json = to_yojson(info);
  let data = Format.asprintf("%a", Json.Print.ppRegular, json);
  Fs.writeFile(~data, path);
};

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
