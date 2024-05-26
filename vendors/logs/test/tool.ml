(* This code is in the public domain. *)

(* Example setup for a simple command line tool with colorful output. *)

let hello _ msg =
  Esy_logs.app (fun m -> m "%s" msg);
  Esy_logs.info (fun m -> m "End-user information.");
  Esy_logs.debug (fun m -> m "Developer information.");
  Esy_logs.err (fun m -> m "Something bad happened.");
  Esy_logs.warn (fun m -> m "Something bad may happen in the future.");
  ()

let setup_log style_renderer level =
 Esy_fmt_tty.setup_std_outputs ?style_renderer ();
  Esy_logs.set_level level;
  Esy_logs.set_reporter (Esy_logs_fmt.reporter ());
  ()


(* Command line interface *)

open Esy_cmdliner

let setup_log =
  let env = Arg.env_var "TOOL_VERBOSITY" in
  Term.(const setup_log $Esy_fmt_cli.style_renderer () $ Esy_logs_cli.level ~env ())

let msg =
  let doc = "The message to output."  in
  Arg.(value & pos 0 string "Hello horrible world!" & info [] ~doc)

let main () =
  match Term.(eval (const hello $ setup_log $ msg, Term.info "tool")) with
  | `Error _ -> exit 1
  | _ -> exit (if Esy_logs.err_count () > 0 then 1 else 0)

let () = main ()
