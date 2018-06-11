/**
 * Information about the task.
 */
module Result = EsyLib.Result;

[@deriving (show, of_yojson, to_yojson)]
type t = {
  timeSpent: float,
  sourceModTime: option(float),
};

let write = (task: BuildTask.t, info: t) => {
  let write = (oc, ()) => {
    Yojson.Safe.pretty_to_channel(oc, to_yojson(info));
    Run.ok;
  };
  Result.join(Bos.OS.File.with_oc(task.infoPath, write, ()));
};

let read = (task: BuildTask.t) => {
  let read =
    Run.(
      if%bind (exists(task.infoPath)) {
        let%bind data = Bos.OS.File.read(task.infoPath);
        let%bind info = Json.parseWith(of_yojson, data);
        Ok(Some(info));
      } else {
        Ok(None);
      }
    );
  switch (read) {
  | Ok(v) => v
  | Error(_) => None
  };
};
