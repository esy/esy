
type ref = string

type remote = string

let clone ~dst ~remote () =
  let cmd = Cmd.(v "git" % "clone" % remote % p dst) in
  ChildProcess.run cmd

let checkout ~ref ~repo () =
  let cmd = Cmd.(v "git" % "-C" % p repo % "checkout" % ref) in
  ChildProcess.run cmd

let lsRemote ?ref ~remote () =
  let open RunAsync.Syntax in
  let ref = Option.orDefault "master" ref in
  let cmd = Cmd.(v "git"  % "ls-remote" % remote % ref) in
  let%bind out = ChildProcess.runOut cmd in
  match out |> String.trim |> String.split_on_char '\n' with
  | [] ->
    let msg = Printf.sprintf "Unable to resolve ref: %s" ref in
    error msg
  | line::_ ->
    return (line |> String.split_on_char '\t' |> List.hd)
