
let clone ~dst ~remote =
  let cmd = Cmd.(v "git" % "clone" % remote % p dst) in
  ChildProcess.run cmd

let checkout ~ref ~repo =
  let cmd = Cmd.(v "git" % "-C" % p repo % "checkout" % ref) in
  ChildProcess.run cmd
