(*---------------------------------------------------------------------------
   Copyright (c) 2015 The esy_logs programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   esy_logs v0.7.0
  ---------------------------------------------------------------------------*)

open Js_of_ocaml

let main _ =
  Esy_logs.set_level @@ Some Esy_logs.Debug;
  Esy_logs.set_reporter @@ Esy_logs_browser.console_reporter ();
  Esy_logs.info (fun m -> m ~header:"START" ?tags:None "Starting main");
  Esy_logs.warn (fun m -> m "Hey be warned by %d." 7);
  Esy_logs.err (fun m -> m "Hey be errored.");
  Esy_logs.debug (fun m -> m "Would you mind to be debugged a bit ?");
  Esy_logs.app (fun m -> m "This is for the application console or stdout.");
  Esy_logs.app (fun m -> m ~header:"HEAD" "Idem but with a header");
  Esy_logs.err (fun m -> m "NO CARRIER");
  Esy_logs.info (fun m -> m "Ending main");
  Js._false

let () = Js.Unsafe.set Dom_html.window "onload" (Dom_html.handler main)

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
