open EsyLib;

let get = url => {
  let cmd = Cmd.(v("curl") % "--silent" % "--fail" % "--location" % url);
  Logs.debug(m => m("curl [get]: %s", url));
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
  Logs.debug(m => m("curl [download]: %s", url));
  ChildProcess.run(cmd);
};
