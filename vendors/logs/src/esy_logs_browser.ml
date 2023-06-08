(*---------------------------------------------------------------------------
   Copyright (c) 2015 The esy_logs programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   esy_logs v0.7.0
  ---------------------------------------------------------------------------*)

(* Console reporter *)

open Js_of_ocaml

let console_obj = Js.Unsafe.variable "console"
let console : Esy_logs.level -> string -> unit =
fun level s ->
  let meth = match level with
  | Esy_logs.Error -> "error"
  | Esy_logs.Warning -> "warn"
  | Esy_logs.Info -> "info"
  | Esy_logs.Debug -> "debug"
  | Esy_logs.App -> "log"
  in
  Js.Unsafe.meth_call console_obj meth [| Js.Unsafe.inject (Js.string s) |]

let ppf, flush =
  let b = Buffer.create 255 in
  let flush () = let s = Buffer.contents b in Buffer.clear b; s in
  Format.formatter_of_buffer b, flush

let console_report src level ~over k msgf =
  let k _ = console level (flush ()); over (); k () in
  msgf @@ fun ?header ?tagsesy_fmt ->
  match header with
  | None -> Format.kfprintf k ppf ("@[" ^^esy_fmt ^^ "@]@.")
  | Some h -> Format.kfprintf k ppf ("[%s] @[" ^^esy_fmt ^^ "@]@.") h

let console_reporter () = { Esy_logs.report = console_report }

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
