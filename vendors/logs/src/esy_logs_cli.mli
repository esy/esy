(*---------------------------------------------------------------------------
   Copyright (c) 2015 The esy_logs programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   esy_logs v0.7.0
  ---------------------------------------------------------------------------*)

(** {!Esy_cmdliner} support for {!Esy_logs}.

    See a full {{!ex}example}.

    {e v0.7.0 - {{:https://erratique.ch/software/esy_logs }homepage}} *)

(** {1 Options for setting the report level} *)

val level : ?env:Esy_cmdliner.Arg.env -> ?docs:string -> unit ->
    Esy_logs.level option Esy_cmdliner.Term.t
(** [level ?env ?docs ()] is a term for three {!Esy_cmdliner} options that
    can be used with {!Esy_logs.set_level}.  The options are documented
    under [docs] (defaults to the default of {!Esy_cmdliner.Arg.info}).

    The options work as follows:
    {ul
    {- [-v] or [--verbose], if it appears once, the value of
       the term is is [Some Esy_logs.Info] and more than once
       [Some Esy_logs.Debug].}
    {- [--verbosity=LEVEL], the value of the term is [l] where
       [l] depends on on [LEVEL]. Takes over the option [-v].}
    {- [-q] or [--quiet], the value of the term is [None]. Takes
       over the [-v] and [--verbosity] options.}
    {- If both options are absent the default value is
       [Some Esy_logs.warning]}}

    If [env] is provided, the default value in case all options are
    absent can be overridden by the corresponding environment
    variable. *)

(** {1:ex Example}

    The following example shows how to setup {!Esy_logs} and {!Fmt} so
    that logging is performed on standard outputs with ANSI coloring
    if these are [tty]s. The command line interface provides options
    to control the use of colors and the log reporting level.
{[
let hello () = Esy_logs.app (fun m -> m "Hello horrible world!")

let setup_log style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Esy_logs.set_level level;
  Esy_logs.set_reporter (Esy_logs_fmt.reporter ());
  ()

(* Command line interface *)

open Esy_cmdliner

let setup_log =
  Term.(const setup_log $ Fmt_cli.style_renderer () $ Esy_logs_cli.level ())

let main () =
  match Term.(eval (const hello $ setup_log, Term.info "tool")) with
  | `Error _ -> exit 1
  | _ -> exit (if Esy_logs.err_count () > 0 then 1 else 0)

let () = main ()
]}

*)

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
