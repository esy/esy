
type ref = string
type commit = string
type remote = string

let runGit cmd =
  let f p =
    let%lwt stdout = Lwt_io.read p#stdout
    and stderr = Lwt_io.read p#stderr in
    match%lwt p#status with
    | Unix.WEXITED 0 ->
      RunAsync.return (stdout)
    | _ ->
      RunAsync.errorf
        "@[<v>command failed: %a@\nstderr:@[<v 2>@\n%a@]@\nstdout:@[<v 2>@\n%a@]@]"
        Cmd.pp cmd Fmt.lines stderr Fmt.lines stdout
  in
  try%lwt
    EsyBashLwt.with_process_full cmd f
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    RunAsync.error msg
  | _ ->
    RunAsync.errorf "cannot execute command: %a" Cmd.pp cmd

let clone ?branch ?depth ~dst ~remote () =
  let open RunAsync.Syntax in
  let%bind cmd = RunAsync.ofBosError (
    let open Cmd in
    let open Result.Syntax in
    let dest = EsyBash.normalizePathForCygwin (Path.show dst) in
    let cmd = v "git" % "clone" in
    let cmd = match branch with
      | Some branch -> cmd % "--branch" % branch
      | None -> cmd
    in
    let cmd = match depth with
      | Some depth -> cmd % "--depth" % string_of_int depth
      | None -> cmd
    in
    return Cmd.(cmd % remote % dest)
  )
  in
  let%bind _ = runGit cmd in
  return ()

let pull ?(force=false) ?(ffOnly=false) ?depth ~remote ~repo ~branchSpec () =
  let open RunAsync.Syntax in
  let cmd =
    let open Cmd in
    let cmd = v "git" % "-C" % p repo % "pull" in
    let cmd = match ffOnly with
      | true -> cmd % "--ff-only"
      | false -> cmd
    in
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
  let%bind _ = runGit cmd in
  return ()

let checkout ~ref ~repo () =
  let open RunAsync.Syntax in
  let cmd = Cmd.(v "git" % "-C" % p repo % "checkout" % ref) in
  let%bind _ = runGit cmd in
  return ()

let lsRemote ?ref ~remote () =
  let open RunAsync.Syntax in
  let cmd = Cmd.(v "git"  % "ls-remote" % remote) in
  let cmd =
    match ref with
    | Some ref -> Cmd.(cmd % ref)
    | None -> cmd
  in
  let%bind out = runGit cmd in
  match out |> String.trim |> String.split_on_char '\n' with
  | [] ->
    return None
  | line::_ ->
    let commit = line |> String.split_on_char '\t' |> List.hd in
    if commit = ""
    then return None
    else return (Some commit)

let isCommitLikeRe = Str.regexp "^[0-9abcdef]+$"
let isCommitLike v =
  let len = String.length v in
  if len >= 6
  then Str.string_match isCommitLikeRe v 0
  else false

module ShallowClone = struct

  let update ~branch ~dst source =

    let getLocalCommit () =
      let remote = EsyBash.normalizePathForCygwin (Path.show dst) in
      lsRemote ~remote ()
    in

    let rec aux ?(retry=true) () =
      let open RunAsync.Syntax in
      if%bind Fs.exists dst then

        let%bind remoteCommit = lsRemote ~ref:branch ~remote:source () in
        let%bind localCommit = getLocalCommit () in

        if remoteCommit = localCommit
        then return ()
        else (
          let branchSpec = branch ^ ":" ^ branch in
          let pulling = pull
            ~branchSpec
            ~force:true
            ~depth:1
            ~remote:source
            ~repo:dst
            ()
          in
          match%lwt pulling with
          | Ok (_) -> return ()
          | Error _ when retry ->
            let%bind () = Fs.rmPath dst in
            aux ~retry:false ()
          | Error err -> Lwt.return (Error err)
        )
      else
        let%bind () = Fs.createDir (Path.parent dst) in
        let%bind () = clone ~branch ~depth:1 ~remote:source ~dst () in
        return ()
    in

    aux ()
end
