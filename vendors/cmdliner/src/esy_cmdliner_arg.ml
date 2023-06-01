(*---------------------------------------------------------------------------
   Copyright (c) 2011 Daniel C. Bünzli. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   %%NAME%% %%VERSION%%
  ---------------------------------------------------------------------------*)

let rev_compare n0 n1 = compare n1 n0

(* Invalid_argument strings **)

let err_not_opt = "Option argument without name"
let err_not_pos = "Positional argument with a name"

(* Documentation formatting helpers *)

let strf = Printf.sprintf
let doc_quote = Esy_cmdliner_base.quote
let doc_alts = Esy_cmdliner_base.alts_str
let doc_alts_enum ?quoted enum = doc_alts ?quoted (List.map fst enum)

let str_of_pp pp v = pp Format.str_formatter v; Format.flush_str_formatter ()

(* Argument converters *)

type 'a parser = string -> [ `Ok of 'a | `Error of string ]
type 'a printer = Format.formatter -> 'a -> unit

type 'a conv = 'a parser * 'a printer
type 'a converter = 'a conv

let default_docv = "VALUE"
let conv ?docv (parse, print) =
  let parse s = match parse s with Ok v -> `Ok v | Error (`Msg e) -> `Error e in
  parse, print

let pconv ?docv conv = conv

let conv_parser (parse, _) =
  fun s -> match parse s with `Ok v -> Ok v | `Error e -> Error (`Msg e)

let conv_printer (_, print) = print
let conv_docv _ = default_docv

let err_invalid s kind = `Msg (strf "invalid value '%s', expected %s" s kind)
let parser_of_kind_of_string ~kind k_of_string =
  fun s -> match k_of_string s with
  | None -> Error (err_invalid s kind)
  | Some v -> Ok v

let some = Esy_cmdliner_base.some

(* Argument information *)

type env = Esy_cmdliner_info.env
let env_var = Esy_cmdliner_info.env

type 'a t = 'a Esy_cmdliner_term.t
type info = Esy_cmdliner_info.arg
let info = Esy_cmdliner_info.arg

(* Arguments *)

let ( & ) f x = f x

let err e = Error (`Parse e)

let parse_to_list parser s = match parser s with
| `Ok v -> `Ok [v]
| `Error _ as e -> e

let try_env ei a parse ~absent = match Esy_cmdliner_info.arg_env a with
| None -> Ok absent
| Some env ->
    let var = Esy_cmdliner_info.env_var env in
    match Esy_cmdliner_info.(eval_env_var ei var) with
    | None -> Ok absent
    | Some v ->
        match parse v with
        | `Ok v -> Ok v
        | `Error e -> err (Esy_cmdliner_msg.err_env_parse env ~err:e)

let arg_to_args = Esy_cmdliner_info.Args.singleton
let list_to_args f l =
  let add acc v = Esy_cmdliner_info.Args.add (f v) acc in
  List.fold_left add Esy_cmdliner_info.Args.empty l

let flag a =
  if Esy_cmdliner_info.arg_is_pos a then invalid_arg err_not_opt else
  let convert ei cl = match Esy_cmdliner_cline.opt_arg cl a with
  | [] -> try_env ei a Esy_cmdliner_base.env_bool_parse ~absent:false
  | [_, _, None] -> Ok true
  | [_, f, Some v] -> err (Esy_cmdliner_msg.err_flag_value f v)
  | (_, f, _) :: (_ ,g, _) :: _  -> err (Esy_cmdliner_msg.err_opt_repeated f g)
  in
  arg_to_args a, convert

let flag_all a =
  if Esy_cmdliner_info.arg_is_pos a then invalid_arg err_not_opt else
  let a = Esy_cmdliner_info.arg_make_all_opts a in
  let convert ei cl = match Esy_cmdliner_cline.opt_arg cl a with
  | [] ->
      try_env ei a (parse_to_list Esy_cmdliner_base.env_bool_parse) ~absent:[]
  | l ->
      try
        let truth (_, f, v) = match v with
        | None -> true
        | Some v -> failwith (Esy_cmdliner_msg.err_flag_value f v)
        in
        Ok (List.rev_map truth l)
      with Failure e -> err e
  in
  arg_to_args a, convert

let vflag v l =
  let convert _ cl =
    let rec aux fv = function
    | (v, a) :: rest ->
        begin match Esy_cmdliner_cline.opt_arg cl a with
        | [] -> aux fv rest
        | [_, f, None] ->
            begin match fv with
            | None -> aux (Some (f, v)) rest
            | Some (g, _) -> failwith (Esy_cmdliner_msg.err_opt_repeated g f)
            end
        | [_, f, Some v] -> failwith (Esy_cmdliner_msg.err_flag_value f v)
        | (_, f, _) :: (_, g, _) :: _ ->
            failwith (Esy_cmdliner_msg.err_opt_repeated g f)
        end
    | [] -> match fv with None -> v | Some (_, v) -> v
    in
    try Ok (aux None l) with Failure e -> err e
  in
  let flag (_, a) =
    if Esy_cmdliner_info.arg_is_pos a then invalid_arg err_not_opt else a
  in
  list_to_args flag l, convert

let vflag_all v l =
  let convert _ cl =
    let rec aux acc = function
    | (fv, a) :: rest ->
        begin match Esy_cmdliner_cline.opt_arg cl a with
        | [] -> aux acc rest
        | l ->
            let fval (k, f, v) = match v with
            | None -> (k, fv)
            | Some v -> failwith (Esy_cmdliner_msg.err_flag_value f v)
            in
            aux (List.rev_append (List.rev_map fval l) acc) rest
        end
    | [] ->
        if acc = [] then v else List.rev_map snd (List.sort rev_compare acc)
    in
    try Ok (aux [] l) with Failure e -> err e
  in
  let flag (_, a) =
    if Esy_cmdliner_info.arg_is_pos a then invalid_arg err_not_opt else
    Esy_cmdliner_info.arg_make_all_opts a
  in
  list_to_args flag l, convert

let parse_opt_value parse f v = match parse v with
| `Ok v -> v
| `Error e -> failwith (Esy_cmdliner_msg.err_opt_parse f e)

let opt ?vopt (parse, print) v a =
  if Esy_cmdliner_info.arg_is_pos a then invalid_arg err_not_opt else
  let absent = Esy_cmdliner_info.Val (lazy (str_of_pp print v)) in
  let kind = match vopt with
  | None -> Esy_cmdliner_info.Opt
  | Some dv -> Esy_cmdliner_info.Opt_vopt (str_of_pp print dv)
  in
  let a = Esy_cmdliner_info.arg_make_opt ~absent ~kind a in
  let convert ei cl = match Esy_cmdliner_cline.opt_arg cl a with
  | [] -> try_env ei a parse ~absent:v
  | [_, f, Some v] ->
      (try Ok (parse_opt_value parse f v) with Failure e -> err e)
  | [_, f, None] ->
      begin match vopt with
      | None -> err (Esy_cmdliner_msg.err_opt_value_missing f)
      | Some optv -> Ok optv
      end
  | (_, f, _) :: (_, g, _) :: _ -> err (Esy_cmdliner_msg.err_opt_repeated g f)
  in
  arg_to_args a, convert

let opt_all ?vopt (parse, print) v a =
  if Esy_cmdliner_info.arg_is_pos a then invalid_arg err_not_opt else
  let absent = Esy_cmdliner_info.Val (lazy "") in
  let kind = match vopt with
  | None -> Esy_cmdliner_info.Opt
  | Some dv -> Esy_cmdliner_info.Opt_vopt (str_of_pp print dv)
  in
  let a = Esy_cmdliner_info.arg_make_opt_all ~absent ~kind a in
  let convert ei cl = match Esy_cmdliner_cline.opt_arg cl a with
  | [] -> try_env ei a (parse_to_list parse) ~absent:v
  | l ->
      let parse (k, f, v) = match v with
      | Some v -> (k, parse_opt_value parse f v)
      | None -> match vopt with
      | None -> failwith (Esy_cmdliner_msg.err_opt_value_missing f)
      | Some dv -> (k, dv)
      in
      try Ok (List.rev_map snd
                (List.sort rev_compare (List.rev_map parse l))) with
      | Failure e -> err e
  in
  arg_to_args a, convert

(* Positional arguments *)

let parse_pos_value parse a v = match parse v with
| `Ok v -> v
| `Error e -> failwith (Esy_cmdliner_msg.err_pos_parse a e)

let pos ?(rev = false) k (parse, print) v a =
  if Esy_cmdliner_info.arg_is_opt a then invalid_arg err_not_pos else
  let absent = Esy_cmdliner_info.Val (lazy (str_of_pp print v)) in
  let pos = Esy_cmdliner_info.pos ~rev ~start:k ~len:(Some 1) in
  let a = Esy_cmdliner_info.arg_make_pos_abs ~absent ~pos a in
  let convert ei cl = match Esy_cmdliner_cline.pos_arg cl a with
  | [] -> try_env ei a parse ~absent:v
  | [v] ->
      (try Ok (parse_pos_value parse a v) with Failure e -> err e)
  | _ -> assert false
  in
  arg_to_args a, convert

let pos_list pos (parse, _) v a =
  if Esy_cmdliner_info.arg_is_opt a then invalid_arg err_not_pos else
  let a = Esy_cmdliner_info.arg_make_pos pos a in
  let convert ei cl = match Esy_cmdliner_cline.pos_arg cl a with
  | [] -> try_env ei a (parse_to_list parse) ~absent:v
  | l ->
      try Ok (List.rev (List.rev_map (parse_pos_value parse a) l)) with
      | Failure e -> err e
  in
  arg_to_args a, convert

let all = Esy_cmdliner_info.pos ~rev:false ~start:0 ~len:None
let pos_all c v a = pos_list all c v a

let pos_left ?(rev = false) k =
  let start = if rev then k + 1 else 0 in
  let len = if rev then None else Some k in
  pos_list (Esy_cmdliner_info.pos ~rev ~start ~len)

let pos_right ?(rev = false) k =
  let start = if rev then 0 else k + 1 in
  let len = if rev then Some k else None in
  pos_list (Esy_cmdliner_info.pos ~rev ~start ~len)

(* Arguments as terms *)

let absent_error args =
  let make_req a acc =
    let req_a = Esy_cmdliner_info.arg_make_req a in
    Esy_cmdliner_info.Args.add req_a acc
  in
  Esy_cmdliner_info.Args.fold make_req args Esy_cmdliner_info.Args.empty

let value a = a

let err_arg_missing args =
  err @@ Esy_cmdliner_msg.err_arg_missing (Esy_cmdliner_info.Args.choose args)

let required (args, convert) =
  let args = absent_error args in
  let convert ei cl = match convert ei cl with
  | Ok (Some v) -> Ok v
  | Ok None -> err_arg_missing args
  | Error _ as e -> e
  in
  args, convert

let non_empty (al, convert) =
  let args = absent_error al in
  let convert ei cl = match convert ei cl with
  | Ok [] -> err_arg_missing args
  | Ok l -> Ok l
  | Error _ as e -> e
  in
  args, convert

let last (args, convert) =
  let convert ei cl = match convert ei cl with
  | Ok [] -> err_arg_missing args
  | Ok l -> Ok (List.hd (List.rev l))
  | Error _ as e -> e
  in
  args, convert

(* Predefined arguments *)

let man_fmts =
  ["auto", `Auto; "pager", `Pager; "groff", `Groff; "plain", `Plain]

let man_fmt_docv = "FMT"
let man_fmts_enum = Esy_cmdliner_base.enum man_fmts
let man_fmts_alts = doc_alts_enum man_fmts
let man_fmts_doc kind =
  strf "Show %s in format $(docv). The value $(docv) must be %s. With `auto',
        the format is `pager` or `plain' whenever the $(b,TERM) env var is
        `dumb' or undefined."
    kind man_fmts_alts

let man_format =
  let doc = man_fmts_doc "output" in
  let docv = man_fmt_docv in
  value & opt man_fmts_enum `Pager & info ["man-format"] ~docv ~doc

let stdopt_version ~docs =
  value & flag & info ["version"] ~docs ~doc:"Show version information."

let stdopt_help ~docs =
  let doc = man_fmts_doc "this help" in
  let docv = man_fmt_docv in
  value & opt ~vopt:(Some `Auto) (some man_fmts_enum) None &
  info ["help"] ~docv ~docs ~doc

(* Predefined converters. *)

let bool = Esy_cmdliner_base.bool
let char = Esy_cmdliner_base.char
let int = Esy_cmdliner_base.int
let nativeint = Esy_cmdliner_base.nativeint
let int32 = Esy_cmdliner_base.int32
let int64 = Esy_cmdliner_base.int64
let float = Esy_cmdliner_base.float
let string = Esy_cmdliner_base.string
let enum = Esy_cmdliner_base.enum
let file = Esy_cmdliner_base.file
let dir = Esy_cmdliner_base.dir
let non_dir_file = Esy_cmdliner_base.non_dir_file
let list = Esy_cmdliner_base.list
let array = Esy_cmdliner_base.array
let pair = Esy_cmdliner_base.pair
let t2 = Esy_cmdliner_base.t2
let t3 = Esy_cmdliner_base.t3
let t4 = Esy_cmdliner_base.t4

(*---------------------------------------------------------------------------
   Copyright (c) 2011 Daniel C. Bünzli

   Permission to use, copy, modify, and/or distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
  ---------------------------------------------------------------------------*)
