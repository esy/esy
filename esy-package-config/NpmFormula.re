[@deriving ord]
type t = list(Req.t);

let empty = [];

let pp = (fmt, deps) =>
  Fmt.pf(fmt, "@[<h>%a@]", Fmt.list(~sep=Fmt.any(", "), Req.pp), deps);

let of_yojson = json => {
  open Result.Syntax;
  let* items = Json.Decode.assoc(json);
  let f = (deps, (name, json)) => {
    let* spec = Json.Decode.string(json);
    let* req = Req.parse(name ++ "@" ++ spec);
    return([req, ...deps]);
  };

  Result.List.foldLeft(~f, ~init=empty, items);
};

let to_yojson = (reqs: t) => {
  let items = {
    let f = (req: Req.t) => (req.name, VersionSpec.to_yojson(req.spec));
    List.map(~f, reqs);
  };

  `Assoc(items);
};

let override = (deps, update) => {
  let map = {
    let f = (map, req: Req.t) => StringMap.add(req.name, req, map);
    let map = StringMap.empty;
    let map = List.fold_left(~f, ~init=map, deps);
    let map = List.fold_left(~f, ~init=map, update);
    map;
  };

  StringMap.values(map);
};

let find = (~name, reqs) => {
  let f = (req: Req.t) => req.name == name;
  List.find_opt(~f, reqs);
};

module Override = {
  [@deriving (ord, show)]
  type t = StringMap.Override.t(Req.t);

  let of_yojson = {
    let req_of_yojson = (name, json) => {
      open Result.Syntax;
      let* spec = Json.Decode.string(json);
      Req.parse(name ++ "@" ++ spec);
    };

    StringMap.Override.of_yojson(req_of_yojson);
  };

  let to_yojson = {
    let req_to_yojson = req => VersionSpec.to_yojson(req.Req.spec);

    StringMap.Override.to_yojson(req_to_yojson);
  };
};
