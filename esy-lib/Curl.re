let get = url => {
  let cmd = Cmd.(v("curl") % "--silent" % "--fail" % "--location" % url);
  print_endline(Cmd.toString(cmd));
  ChildProcess.runOut(cmd);
};

let download = (~output, url) => {
  let cmd =
    Cmd.(
      v("curl")
      % "--silent"
      % "--fail"
      % "--location"
      % "--output"
      % p(output)
      % url
    );
  ChildProcess.run(cmd);
};
