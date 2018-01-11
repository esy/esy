let readFile = (path: Path.t) => {
  let path = Path.to_string(path);
  let%lwt ic = Lwt_io.open_file(~mode=Lwt_io.Input, path);
  let%lwt data = Lwt_io.read(ic);
  Lwt.return(data);
};

let readJsonFile = (path: Path.t) => {
  let%lwt data = readFile(path);
  Lwt.return(Yojson.Safe.from_string(data));
};

let exists = (path: Path.t) => {
  let path = Path.to_string(path);
  Lwt_unix.file_exists(path);
};
