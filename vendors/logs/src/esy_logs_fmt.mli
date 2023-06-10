(*---------------------------------------------------------------------------
   Copyright (c) 2015 The esy_logs programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   esy_logs v0.7.0
  ---------------------------------------------------------------------------*)

(** {!Format} colorful reporter for {!Esy_logs}.


    {e v0.7.0 - {{:https://erratique.ch/software/esy_logs }homepage}} *)

(** {1 Reporter} *)

val reporter :
  ?pp_header:(Esy_logs.level * string option) Esy_fmt.t ->
  ?app:Format.formatter ->
  ?dst:Format.formatter -> unit -> Esy_logs.reporter
(** [reporter] is like {!Esy_logs.format_reporter} except ANSI colors may be
    used in message header rendering if the formatters are configured to do so;
    see {!Esy_fmt.set_style_renderer} and {!Fmt_tty}.

    Consult a full command line {{!Esy_logs_cli.ex}setup example}. *)

(** {1:cheader Colored message headers} *)

val app_style : Esy_fmt.style
(** [app_style] is the style used to render headers at app level. *)

val err_style : Esy_fmt.style
(** [err_style] is the style used to render headers at error level. *)

val warn_style : Esy_fmt.style
(** [warn_style] is the style used to render headers at warning level. *)

val info_style : Esy_fmt.style
(** [info_style] is the style used to render headers at info level. *)

val debug_style : Esy_fmt.style
(** [debug_style] is the style used to render headers at debug level. *)

val pp_header : (Esy_logs.level * string option) Esy_fmt.t
(** [pp_header] is like {!Esy_logs.pp_header} but may use ANSI colors if the
    formatter is configured to do so, see {!Esy_fmt.set_style_renderer} and
    {!Fmt_tty}. *)

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
