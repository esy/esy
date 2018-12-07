module String = Astring.String

module Meta = struct
  type t = {code : int} [@@deriving of_yojson]
end

type response =
  | Success of string
  | NotFound

type headers = string StringMap.t

type url = string

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
    let%lwt stdout =
      Lwt.finalize
        (fun () -> Lwt_io.read p#stdout)
        (fun () -> Lwt_io.close p#stdout)
    and stderr = Lwt_io.read p#stderr in
    match%lwt p#status with
    | Unix.WEXITED 0 -> begin
      match parseStdout stdout with
      | Ok (stdout, _meta) -> RunAsync.return (Success stdout)
      | Error err -> Lwt.return (Error err)
      end
    | _ -> begin
      match parseStdout stdout with
      | Ok (_stdout, meta) when meta.Meta.code = 404 ->
        RunAsync.return NotFound
      | Ok (_stdout, meta) ->
        RunAsync.errorf
          "@[<v>error running curl: %a:@\ncode: %i@\nstderr:@[<v 2>@\n%a@]@]"
          Cmd.pp cmd meta.code Fmt.lines stderr
      | _ ->
        RunAsync.errorf
          "@[<v>error running curl: %a:@\nstderr:@[<v 2>@\n%a@]@]"
          Cmd.pp cmd Fmt.lines stderr
    end
  in
  try%lwt
    EsyBashLwt.with_process_full cmd f
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    RunAsync.error msg
  | _ ->
    RunAsync.error "error running subprocess"

let getOrNotFound ?accept url =
  let cmd = Cmd.(
    v "curl"
    % "--silent"
    % "--fail"
    % "--location" % url
  ) in
  let cmd =
    match accept with
    | Some accept -> Cmd.(cmd % "--header" % accept)
    | None -> cmd
  in
  runCurl cmd

let head url =
  let open RunAsync.Syntax in

  let parseResponse response =
    match StringLabels.split_on_char ~sep:'\n' response with
    | [] -> StringMap.empty
    | _::lines ->
      let f headers line =
        match String.cut ~sep:":" line with
        | None -> headers
        | Some (name, value) ->
          let name = name |> String.trim |> String.Ascii.lowercase in
          let value = String.trim value in
          StringMap.add name value headers
      in
      List.fold_left ~f ~init:StringMap.empty lines
  in

  let cmd = Cmd.(
    v "curl"
    % "--head"
    % "--silent"
    % "--fail"
    % "--location" % url
  ) in
  match%bind runCurl cmd with
  | Success response -> return (parseResponse response)
  | NotFound -> RunAsync.error "not found"

let get ?accept url =
  let open RunAsync.Syntax in
  match%bind getOrNotFound ?accept url with
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
