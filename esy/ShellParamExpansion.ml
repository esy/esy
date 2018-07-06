include ShellParamExpansionParser

let sanitizeShellParameters str = 
    let backSlashRegex = Str.regexp "\\\\" in
    let sanitizedString = Str.global_replace backSlashRegex "/" str in
    sanitizedString;;


let parse_exn v =
  let lexbuf = Lexing.from_string v in
  read [] `Init lexbuf

let parse src =
  try Ok (parse_exn src)
  with
  | UnmatchedChar (pos, _) ->
    let cnum = pos.Lexing.pos_cnum - 1 in
    let msg = ParseUtil.formatParseError ~src ~cnum "unknown character" in
    Run.error msg
  | UnknownShellEscape (pos, str) ->
    let cnum = pos.Lexing.pos_cnum - String.length str in
    let msg = ParseUtil.formatParseError ~src ~cnum "unknown shell escape sequence" in
    Run.error msg

type scope = string -> string option

let render ?(fallback=Some "") ~(scope : scope) v =
  let open Run.Syntax in
  let%bind tokens = parse v in
  let f segments = function
    | String v -> Ok (v::segments)
    | Var (name, default) ->
      begin match scope name, default, fallback with
      | Some v, _, _
      | None, Some v, _ -> Ok (v::segments)
      | None, None, Some v -> Ok (v::segments)
      | _, _, _ -> Run.error ("unable to resolve: $" ^ name)
      end
  in
  let%bind segments = Result.List.foldLeft ~f ~init:[] tokens in
  Ok (segments |> List.rev |> String.concat "" |> sanitizeShellParameters)
