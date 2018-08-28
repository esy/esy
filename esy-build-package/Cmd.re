include Bos.Cmd;

let pp = (fmt, cmd) => {
  let args = cmd |> to_list |> List.map(Filename.quote);
  let pp = Fmt.(hbox(list(~sep=unit(" "), string)));
  pp(fmt, args);
};
