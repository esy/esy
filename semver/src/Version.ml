open Import

include Types.Version

let make ?(prerelease=[]) ?(build=[]) major minor patch =
  {major; minor; patch; prerelease; build}

let next_major v = make (v.major + 1) 0 0
let next_minor v = make v.major (v.minor + 1) 0
let next_patch v = make v.major v.minor (v.patch + 1)

let is_prerelease = function
  | {prerelease = []; _} -> false
  | _ -> true

let strip_prerelease v = make v.major v.minor v.patch

module Compare = struct
  let compare_prerelease_id a b =
    match a, b with
    | N _, A _ -> -1
    | A _, N _ -> 1
    | N a, N b -> Int.compare a b
    | A a, A b -> String.compare a b

  let compare_prerelease a b =
    let rec aux a b =
      match a, b with
      | [], [] -> 0
      | [], _ -> (-1)
      | _, [] -> 1
      | x::xs, y::ys ->
        begin match compare_prerelease_id x y with
        | 0 -> aux xs ys
        | v -> v
        end
    in
    match a, b with
    | [], [] -> 0
    | [], _ -> 1
    | _, [] -> -1
    | a, b -> aux a b

  let compare_build a b =
    let rec aux a b =
      match a, b with
      | [], [] -> 0
      | [], _ -> (-1)
      | _, [] -> 1
      | x::xs, y::ys ->
        begin match String.compare x y with
        | 0 -> aux xs ys
        | v -> v
        end
    in
    match a, b with
    | [], [] -> 0
    | [], _ -> 1
    | _, [] -> -1
    | a, b -> aux a b

  let compare a b =
    match Int.compare a.major b.major with
    | 0 ->
      begin match Int.compare a.minor b.minor with
      | 0 ->
        begin match Int.compare a.patch b.patch with
        | 0 ->
          begin match compare_prerelease a.prerelease b.prerelease with
          | 0 -> compare_build a.build b.build
          | v -> v
          end
        | v -> v
        end
      | v -> v
      end
    | v -> v
end

let compare = Compare.compare

let equal a b = compare a b = 0

let parse v =
  let lexbuf = Lexing.from_string v in
  match Parser.parse_version Lexer.(make main ()) lexbuf with
  | exception Lexer.Error msg -> Error msg
  | exception Parser.Error ->
    let pos = lexbuf.Lexing.lex_curr_p.pos_cnum in
    let msg = Printf.sprintf "error parsing: %i column" pos in
    Error msg
  | v -> Ok v

let parse_exn v =
  match parse v with
  | Ok v -> v
  | Error msg -> failwith msg

let pp fmt v =
  Format.fprintf fmt "%i.%i.%i" v.major v.minor v.patch;
  let () =
    match v.prerelease with
    | [] -> ()
    | parts ->
      Format.pp_print_char fmt '-';
      let pp_item fmt = function
        | A p -> Pp.pp_string fmt p
        | N p -> Pp.pp_int fmt p
      in
      Pp.(pp_list (pp_const ".") pp_item) fmt parts
  in
  let () =
    match v.build with
    | [] -> ()
    | parts ->
      Format.pp_print_char fmt '+';
      Pp.(pp_list (pp_const ".") pp_string) fmt parts
  in
  ()

let pp_inspect fmt v =
  let pp_item fmt = function
    | A p -> Format.pp_print_string fmt p
    | N p -> Format.pp_print_int fmt p
  in
  Format.fprintf fmt
    "%i.%i.%i [%a] [%a]"
    v.major v.minor v.patch
    Pp.(pp_list (pp_const ";") pp_item) v.prerelease
    Pp.(pp_list (pp_const ";") pp_string) v.build

let show v = Format.asprintf "%a" pp v
