let apply ~strip ~root ~patch () =
  let cmd = Cmd.(
    v "patch"
    % "--directory" % p root
    % "--strip" % string_of_int strip
    % "--input" % p patch
  ) in
  ChildProcess.run cmd
