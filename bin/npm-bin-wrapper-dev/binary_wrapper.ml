let windows = Sys.os_type = "Win32"
let cwd = Sys.getcwd ()
let path_sep = '/'
let path_sep_str = String.make 1 path_sep

let caseInsensitiveEqual i j =
  String.lowercase_ascii i = String.lowercase_ascii j

let caseInsensitiveHash k = Hashtbl.hash (String.lowercase_ascii k)

module EnvHash = struct
  type t = string

  let equal = if windows then caseInsensitiveEqual else ( = )
  let hash = if windows then caseInsensitiveHash else Hashtbl.hash
end

module EnvHashtbl = Hashtbl.Make (EnvHash)

let is_root p =
  if windows then
    match String.split_on_char ':' p with
    | [ drive ] when String.length drive = 1 -> true
    | [ drive; p ]
      when String.length drive = 1 && (String.equal p "/" || String.equal p "\\")
      ->
        true
    | _ -> false
  else String.equal p "/" || String.equal p "//"

let is_abs p =
  if windows then
    match String.split_on_char ':' p with
    | drive :: _ when String.length drive = 1 -> true
    | _ -> false
  else String.length p > 0 && String.get p 0 = '/'

let normalize p =
  let p = Str.global_substitute (Str.regexp "\\") (fun _ -> "/") p in
  let parts = String.split_on_char '/' p in
  let need_leading_sep = (not windows) && is_abs p in
  let f parts part =
    match (part, parts) with
    | "", parts -> parts
    | ".", parts -> parts
    | "..", [] -> parts
    | "..", part :: [] -> if windows then part :: [] else []
    | "..", _ :: parts -> parts
    | part, parts -> part :: parts
  in
  let p = String.concat path_sep_str (List.rev (List.fold_left f [] parts)) in
  if need_leading_sep then "/" ^ p else p

let is_symlink p =
  match Unix.lstat p with
  | { Unix.st_kind = Unix.S_LNK; _ } -> true
  | _ -> false
  | exception Unix.Unix_error _ -> false

let rec resolve_path p =
  let p = if is_abs p then p else normalize (Filename.concat cwd p) in

  if is_root p then p
  else if is_symlink p then
    let target = Unix.readlink p in
    if is_abs target then resolve_path target
    else resolve_path (normalize (Filename.concat (Filename.dirname p) target))
  else Filename.concat (resolve_path (Filename.dirname p)) (Filename.basename p)

let curEnvMap =
  let curEnv = Unix.environment () in
  let table = EnvHashtbl.create (Array.length curEnv) in
  let f item =
    try
      let idx = String.index item '=' in
      let name = String.sub item 0 idx in
      let value =
        if String.length item - 1 = idx then ""
        else String.sub item (idx + 1) (String.length item - idx - 1)
      in
      EnvHashtbl.replace table name value
    with Not_found -> ()
  in
  Array.iter f curEnv;
  table

let expandEnv env =
  let findVarRe = Str.regexp "\\$\\([a-zA-Z0-9_]+\\)" in
  let replace v =
    let name = Str.matched_group 1 v in
    try EnvHashtbl.find curEnvMap name with Not_found -> ""
  in
  let f (name, value) =
    let value = Str.global_substitute findVarRe replace value in
    EnvHashtbl.replace curEnvMap name value
  in
  Array.iter f env;
  let f name value items =
    let value =
      if String.equal (String.lowercase_ascii name) "comspec" then value
      else normalize value
    in
    (name ^ "=" ^ value) :: items
  in
  Array.of_list (EnvHashtbl.fold f curEnvMap [])

let this_executable = resolve_path Sys.executable_name

(** this expands not rewritten store prefix _______ into a local release path *)
let expandFallback storePrefix =
  let dummyPrefix = String.make (String.length storePrefix) '_' in
  let dirname = Filename.dirname this_executable in
  let pattern = Str.regexp dummyPrefix in
  let storePrefix =
    let ( / ) = Filename.concat in
    normalize (dirname / ".." / "3")
  in
  let rewrite value =
    Str.global_substitute pattern (fun _ -> storePrefix) value
  in
  rewrite

let expandFallbackEnv storePrefix env =
  Array.map (expandFallback storePrefix) env

let () =
  let env = Package.environment in
  let program = Package.program in
  let storePrefix = Package.store_prefix in
  let expandedEnv = expandFallbackEnv storePrefix (expandEnv env) in
  let shellEnv =
    match Sys.getenv_opt "SHELL" with
    | Some v -> [| "SHELL=" ^ v |]
    | None -> [| "SHELL=/bin/sh" |]
  in
  let expandedEnv = Array.append expandedEnv shellEnv in
  if Array.length Sys.argv = 2 && Sys.argv.(1) = "----where" then
    print_endline (expandFallback storePrefix program)
  else if Array.length Sys.argv = 2 && Sys.argv.(1) = "----env" then
    Array.iter print_endline expandedEnv
  else
    let program = expandFallback storePrefix program in
    Sys.argv.(0) <- program;
    if windows then
      let pid =
        Unix.create_process_env program Sys.argv expandedEnv Unix.stdin
          Unix.stdout Unix.stderr
      in
      let _, status = Unix.waitpid [] pid in
      match status with
      | WEXITED code -> exit code
      | WSIGNALED code -> exit code
      | WSTOPPED code -> exit code
    else Unix.execve program Sys.argv expandedEnv
