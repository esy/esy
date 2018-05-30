
type ref = string

type remote = string

let clone ?branch ?depth ~dst ~remote () =
  let cmd =
    let open Cmd in
    let cmd = v "git" % "clone" in
    let cmd = match branch with
      | Some branch -> cmd % "--branch" % branch
      | None -> cmd
    in
    let cmd = match depth with
      | Some depth -> cmd % "--depth" % string_of_int depth
      | None -> cmd
    in
    Cmd.(cmd % remote % p dst)
  in
  ChildProcess.run cmd

let pull ?(force=false) ?depth ~remote ~repo ~branchSpec () =
  let cmd =
    let open Cmd in
    let cmd = v "git" % "-C" % p repo % "pull" in
    let cmd = match force with
      | true -> cmd % "--force"
      | false -> cmd
    in
    let cmd = match depth with
      | Some depth -> cmd % "--depth" % string_of_int depth
      | None -> cmd
    in
    Cmd.(cmd % remote % branchSpec)
  in
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

module ShallowClone = struct
  let update ~branch ~dst source =
    let open RunAsync.Syntax in
    if%bind Fs.exists dst then
      let branchSpec = branch ^ ":" ^ branch in
      pull
        ~branchSpec
        ~depth:1
        ~force:true
        ~remote:source
        ~repo:dst
        ()
    else
      let%bind () = Fs.createDirectory (Path.parent dst) in
      clone ~branch ~depth:1 ~remote:source ~dst ()
end
