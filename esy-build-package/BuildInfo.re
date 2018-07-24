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
  let write = (oc, ()) => {
    Yojson.Safe.pretty_to_channel(oc, to_yojson(info));
    Run.ok;
  };
  Result.join(Bos.OS.File.with_oc(path, write, ()));
};

let ofFile = (path: EsyLib.Path.t) =>
  if%bind (exists(path)) {
    let%bind data = Bos.OS.File.read(path);
    let json = Yojson.Safe.from_string(data);
    switch (of_yojson(json)) {
    | Ok(v) => Ok(Some(v))
    | Error(_err) => Ok(None)
    };
  } else {
    Ok(None);
  };
