let parseWith = (parser, data) => {
  let json = Yojson.Safe.from_string(data);
  switch (parser(json)) {
  | Ok(value) => Ok(value)
  | Error(msg) => Error(`Msg(msg))
  };
};
