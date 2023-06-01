(* Example from the documentation, this code is in public domain. *)

let revolt () = print_endline "Revolt!"

open Esy_cmdliner

let revolt_t = Term.(const revolt $ const ())

let () = Term.(exit @@ eval (revolt_t, Term.info "revolt"))
