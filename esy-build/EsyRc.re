open RunAsync.Syntax;

[@deriving of_yojson]
type t = {prefixPath: option(Path.t)};

let empty = {prefixPath: None};

let normalizePath = (~path, p) =>
  if (Path.isAbs(p)) {
    p;
  } else {
    Path.(normalize(path /\/ p));
  };

let ofFile = (~basePath, filename) => {
  let* data = Fs.readFile(filename);
  let* json =
    switch (Json.parse(data)) {
    | Ok(json) => return(json)
    | Error(err) =>
      errorf(
        "expected %a to be a JSON file but got error: %a",
        Path.pp,
        filename,
        Run.ppError,
        err,
      )
    };

  let* rc = RunAsync.ofStringError(of_yojson(json));
  let rc = {
    prefixPath: Option.map(~f=normalizePath(~path=basePath), rc.prefixPath),
  };
  return(rc);
};

let ofFileOpt = (~basePath, filename) => {
  let rc = {
    let* data = Fs.readFile(filename);
    let* json =
      switch (Json.parse(data)) {
      | Ok(json) => return(json)
      | Error(err) =>
        errorf(
          "expected %a to be a JSON file but got error: %a",
          Path.pp,
          filename,
          Run.ppError,
          err,
        )
      };

    let* rc = RunAsync.ofStringError(of_yojson(json));
    let rc = {
      prefixPath:
        Option.map(~f=normalizePath(~path=basePath), rc.prefixPath),
    };
    return(Some(rc));
  };

  RunAsync.try_(~catch=_ => return(None), rc);
};

let ofPath = path => {
  let filename = Path.(path / ".esyrc");
  let filenameInHome = Path.(Path.homePath() / ".esyrc");

  if%bind (Fs.exists(filename)) {
    ofFile(~basePath=path, filename);
  } else {
    if%bind (Fs.exists(filenameInHome)) {
      ofFile(~basePath=path, filenameInHome);
    } else {
      return(empty);
    };
  };
};

let ofPathOpt = path => {
  let filename = Path.(path / ".esyrc");
  let filenameInHome = Path.(Path.homePath() / ".esyrc");

  if%bind (Fs.exists(filename)) {
    ofFileOpt(~basePath=path, filename);
  } else {
    if%bind (Fs.exists(filenameInHome)) {
      ofFileOpt(~basePath=path, filenameInHome);
    } else {
      return(Some(empty));
    };
  };
};
