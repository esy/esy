
(* let runSolver ?(strategy=Strategies.trendy) ~univ root = *)
(*   let cudfUniverse, cudfVersionMap = Universe.toCudf univ in *)

(*   let cudfName = root.Package.name in *)
(*   let cudfVersion = *)
(*     VersionMap.findCudfVersionExn *)
(*       ~name:(root.Package.name) *)
(*       ~version:(root.Package.version) *)
(*       cudfVersionMap *)
(*   in *)

(*   let solution = *)
(*     let request = { *)
(*       Cudf.default_request with *)
(*       install = [cudfName, Some (`Eq, cudfVersion)] *)
(*     } in *)
(*     let preamble = Cudf.default_preamble in *)
(*     Mccs.resolve_cudf *)
(*       ~verbose:false *)
(*       ~timeout:5. *)
(*       strategy *)
(*       (preamble, cudfUniverse, request) *)
(*   in *)

(*   match solution with *)
(*   | None -> None *)
(*   | Some (_preamble, universe) -> *)
(*     let cudfPackagesToInstall = *)
(*       Cudf.get_packages *)
(*         ~filter:(fun p -> p.Cudf.installed) *)
(*         universe *)
(*     in *)

(*     let packagesToInstall = *)
(*       cudfPackagesToInstall *)
(*       |> List.filter ~f:(fun p -> p.Cudf.package <> root.Package.name) *)
(*       |> List.map ~f:(fun p -> *)
(*           let version = *)
(*             VersionMap.findVersionExn *)
(*               ~name:p.Cudf.package *)
(*               ~cudfVersion:p.Cudf.version *)
(*               cudfVersionMap *)
(*           in *)
(*           match Universe.findVersion ~name:p.Cudf.package ~version univ with *)
(*           | Some pkg -> pkg *)
(*           | None -> *)
(*             let msg = Printf.sprintf *)
(*               "inconsistent state: missing package %s@%s" *)
(*               p.Cudf.package (Version.toString version) *)
(*             in *)
(*             failwith msg) *)
(*     in Some packagesToInstall *)

module Solver = struct
  let runWithFilename ?(timeout=5.) ?(strategy="-notuptodate") filename =
    let preamble, univ, req = Cudf_parser.load_from_file filename in
    let preamble =
      match preamble with
      | Some preamble -> preamble
      | None -> Cudf.default_preamble
    in
    let req =
      match req with
      | Some req -> req
      | None -> Cudf.default_request
    in
    let solution =  Mccs.resolve_cudf
      ~verbose:false
      ~timeout
      strategy
      (preamble, univ, req)
    in

    match solution with
    | Some solution ->
      Cudf_printer.pp_solution stdout solution;
      `Ok ()
    | None ->
      `Error (false, "no solution found")
end

module CommandLineInterface = struct
  open Cmdliner

  let exits = Term.default_exits
  let docs = Manpage.s_common_options
  let sdocs = Manpage.s_common_options
  let cwd = Path.v (Sys.getcwd ())
  let version = "0.1.0"


  let timeout =
    let doc = "Specifies timeout." in
    Arg.(
      value
      & opt (some float) None
      & info ["timeout"; "t"] ~docs ~doc
    )

  let strategy =
    let doc = "Specifies optimization criteria to use." in
    Arg.(
      required
      & pos 0 (some string) None
      & info [] ~doc ~docv:"STRATEGY"
    )

  let filename =
    let doc = "Path to CUDF document file to solve." in
    Arg.(
      required
      & pos 1  (some file) None
      & info [] ~doc ~docv:"PATH"
    )

  let defaultCommand =
    let doc = "Solve CUDF dependency problem" in
    let info = Term.info "esy-solve" ~version ~doc ~sdocs ~exits in
    let cmd timeout strategy filename =
      Solver.runWithFilename ?timeout ~strategy filename
    in
    Term.(ret (const cmd $ timeout $ strategy $ filename)), info

  let run () =
    Printexc.record_backtrace true;
    Term.(exit (eval ~argv:Sys.argv defaultCommand))
end

let () = CommandLineInterface.run()
