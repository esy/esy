open EsyLib;

let get = url => {
  let cmd = Cmd.(v("curl") % "--silent" % "--fail" % "--location" % url);
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
