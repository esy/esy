module Cmd = EsyLib.Cmd
module ChildProcess = EsyLib.ChildProcess

let unpack ?stripComponents ~dst ~filename =
  let cmd =
    let cmd = Cmd.(v "tar" % "xf" % p filename) in
    let cmd =
      match stripComponents with
      | Some stripComponents ->
        Cmd.(cmd % "--strip-components" % string_of_int(stripComponents))
      | None -> cmd
    in
    let cmd = Cmd.(cmd % "-C" % p dst) in
    cmd
  in
  ChildProcess.run cmd

let create ~src ~filename =
  let cmd = Cmd.(v "tar" % "czf" % p filename % p src) in
  ChildProcess.run cmd
