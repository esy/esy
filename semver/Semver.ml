type t = {
  major : int;
  minor : int;
  patch : int;
  prerelease : [`Alphanumeric of string | `Numeric of int ] list;
  build : string list;
}

let compare_prerelease_id a b =
  match a, b with
  | `Numeric _, `Alphanumeric _ -> -1
  | `Alphanumeric _, `Numeric _ -> 1
  | `Numeric a, `Numeric b -> Int.compare a b
  | `Alphanumeric a, `Alphanumeric b -> String.compare a b

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

let parse v =
  let lexbuf = Lexing.from_string v in
  match Lexer.version lexbuf with
  | (major, minor, patch), prerelease, build ->
    Ok {major; minor; patch; prerelease; build;}
  | exception Lexer.Error msg ->
    Error msg

let pp_list sep pp_item fmt xs =
  match xs with
  | [] -> ()
  | [x] -> pp_item fmt x
  | x::xs ->
    pp_item fmt x;
    List.iter
      (fun p -> Format.pp_print_char fmt sep; pp_item fmt p)
      xs

let pp fmt v =
  Format.fprintf fmt "%i.%i.%i" v.major v.minor v.patch;
  let () =
    match v.prerelease with
    | [] -> ()
    | parts ->
      Format.pp_print_char fmt '-';
      let pp_item fmt = function
        | `Alphanumeric p -> Format.pp_print_string fmt p
        | `Numeric p -> Format.pp_print_int fmt p
      in
      pp_list '.' pp_item fmt parts
  in
  let () =
    match v.build with
    | [] -> ()
    | parts ->
      Format.pp_print_char fmt '+';
      pp_list '.' Format.pp_print_string fmt parts
  in
  ()

let show v =
  Format.asprintf "%a" pp v
