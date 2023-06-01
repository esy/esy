(*---------------------------------------------------------------------------
   Copyright (c) 2015 The esy_fmt programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
  ---------------------------------------------------------------------------*)

(** {!Esy_cmdliner} support for [Esy_fmt]. *)

(** {1 Option for setting the style renderer} *)

val style_renderer : ?env:Esy_cmdliner.Arg.env -> ?docs:string -> unit ->
  Esy_fmt.style_renderer option Esy_cmdliner.Term.t
(** [style_renderer ?env ?docs ()] is a {!Esy_cmdliner} option [--color] that can
    be directly used with the optional arguments of
    {{!Esy_fmt_tty.tty_setup}TTY setup} or to control
    {{!Esy_fmt.set_style_renderer}style rendering}.  The option is
    documented under [docs] (defaults to the default in
    {!Esy_cmdliner.Arg.info}).

    The option is a tri-state enumerated value that when used with
    {{!Esy_fmt_tty.tty_setup}TTY setup} takes over the automatic setup:
    {ul
    {- [--color=never], the value is [Some `None], forces no styling.}
    {- [--color=always], the value is [Some `Ansi], forces ANSI styling.}
    {- [--color=auto] or absent, the value is [None], automatic setup
       takes place.}}

    If [env] is provided, the option default value ([None]) can be
    overridden by the corresponding environment variable. *)

(*---------------------------------------------------------------------------
   Copyright (c) 2015 The esy_fmt programmers

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
