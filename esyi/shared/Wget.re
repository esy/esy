module Cmd = EsyLib.Cmd;

let get = (~output=?, url) => {
  let cmd = {
    let cmd = Cmd.(v("curl") % "--silent" % "--fail" % "--location");
    let cmd =
      switch (output) {
      | Some(output) => Cmd.(cmd % "--output" % p(output))
      | None => cmd
      };
    Cmd.(cmd % url);
  };
  let (lines, good) = ExecCommand.execSync(~cmd=Cmd.toString(cmd), ());
  if (good) {
    Some(String.concat("\n", lines));
  } else {
    None;
  };
};
