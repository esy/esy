/**
 * Information about the spec.
 */
[@deriving (show, of_yojson, to_yojson)]
type t = {
  timeSpent: float,
  sourceModTime: option(float)
};

let write = (spec: BuildSpec.t, info: t) => {
  let write = (oc, ()) => {
    Yojson.Safe.pretty_to_channel(oc, to_yojson(info));
    Run.ok;
  };
  Result.join(Bos.OS.File.with_oc(spec.infoPath, write, ()));
};

let read = (spec: BuildSpec.t) => {
  let read =
    Run.(
      if%bind (exists(spec.infoPath)) {
        let%bind data = Bos.OS.File.read(spec.infoPath);
        let%bind info = Json.parseWith(of_yojson, data);
        Ok(Some(info));
      } else {
        Ok(None);
      }
    );
  switch read {
  | Ok(v) => v
  | Error(_) => None
  };
};
