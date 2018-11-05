let dirname = Filename.dirname Sys.executable_name
let filename = Filename.concat dirname "test.fastreplacestring"

let%expect_test "it is working" =
  let () =
    let oc = open_out filename in
    Printf.fprintf oc "someHeLlostring\nHeLlo at the beginning\nat the end HeLlo\n";
    close_out oc;
  in

  let () =
    match Fastreplacestring.replace filename "HeLlo" "HELLO" with
    | Ok () -> ()
    | Error err -> failwith err
  in

  let ic = open_in filename in
  print_endline (input_line ic);
  print_endline (input_line ic);
  print_endline (input_line ic);
  close_in ic;
  [%expect {|
    someHELLOstring
    HELLO at the beginning
    at the end HELLO |}]
