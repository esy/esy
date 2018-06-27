module String = Astring.String

module Meta = struct
  type t = {code : int} [@@deriving of_yojson]
end

type response =
  | Success of string
  | NotFound

let parseStdout stdout =
  let open Run.Syntax in
  match String.cut ~rev:true ~sep:"\n" stdout with
  | Some (stdout, meta) ->
    let%bind meta = Json.parseStringWith Meta.of_yojson meta in
    return (stdout, meta)
  | None ->
    error "unable to parse metadata from a curl response"

let runCurl cmd =
  let cmd = Cmd.(
    cmd
    % "--write-out"
    % {|\n{"code": %{http_code}}|}
  ) in
  let f p =
    let%lwt stdout = Lwt_io.read p#stdout
    and stderr = Lwt_io.read p#stderr in
    match%lwt p#status with
    | Unix.WEXITED 0 ->
      RunAsync.return (Success stdout)
    | _ -> begin
      match parseStdout stdout with
      | Ok (_stdout, meta) when meta.Meta.code = 404 ->
        RunAsync.return NotFound
      | _ ->
        Logs_lwt.err (fun m -> m
          "@[<v>command failed: %a@\nstderr:@[<v 2>@\n%s@]@\nstdout:@[<v 2>@\n%s@]@]"
          Cmd.pp cmd stderr stdout
        );%lwt
        RunAsync.error "error running command"
    end
  in
  try%lwt
    let cmd = Cmd.getToolAndLine cmd in
    Lwt_process.with_process_full cmd f
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    RunAsync.error msg
  | _ ->
    RunAsync.error "error running subprocess"

let getOrNotFound url =
  let cmd = Cmd.(
    v "curl"
    % "--silent"
    % "--fail"
    % "--location" % url
  ) in
  runCurl cmd

let get url =
  let open RunAsync.Syntax in
  match%bind getOrNotFound url with
  | Success result -> RunAsync.return result
  | NotFound -> RunAsync.error "not found"

let download ~output  url =
  let open RunAsync.Syntax in
  let cmd = Cmd.(
    v "curl"
    % "--silent"
    % "--fail"
    % "--location" % url
    % "--output" % p output
  ) in
  match%bind runCurl cmd with
  | Success _ -> RunAsync.return ()
  | NotFound -> RunAsync.error "not found"
