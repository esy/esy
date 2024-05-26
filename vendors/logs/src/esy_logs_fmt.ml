(*---------------------------------------------------------------------------
   Copyright (c) 2015 The esy_logs programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   esy_logs v0.7.0
  ---------------------------------------------------------------------------*)

let app_style = `Cyan
let err_style = `Red
let warn_style = `Yellow
let info_style = `Blue
let debug_style = `Green

let pp_header ~pp_h ppf (l, h) = match l with
| Esy_logs.App ->
    begin match h with
    | None -> ()
    | Some h ->Esy_fmt.pf ppf "[%a] "Esy_fmt.(styled app_style string) h
    end
| Esy_logs.Error ->
    pp_h ppf err_style (match h with None -> "ERROR" | Some h -> h)
| Esy_logs.Warning ->
    pp_h ppf warn_style (match h with None -> "WARNING" | Some h -> h)
| Esy_logs.Info ->
    pp_h ppf info_style (match h with None -> "INFO" | Some h -> h)
| Esy_logs.Debug ->
    pp_h ppf debug_style (match h with None -> "DEBUG" | Some h -> h)

let pp_exec_header =
  let x = match Array.length Sys.argv with
  | 0 -> Filename.basename Sys.executable_name
  | n -> Filename.basename Sys.argv.(0)
  in
  let pp_h ppf style h =Esy_fmt.pf ppf "%s: [%a] " x Esy_fmt.(styled style string) h in
  pp_header ~pp_h

let reporter ?(pp_header = pp_exec_header) ?app ?dst () =
  Esy_logs.format_reporter ~pp_header ?app ?dst ()

let pp_header =
  let pp_h ppf style h =Esy_fmt.pf ppf "[%a]" Esy_fmt.(styled style string) h in
  pp_header ~pp_h

(*---------------------------------------------------------------------------
   Copyright (c) 2015 The esy_logs programmers

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
