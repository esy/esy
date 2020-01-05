let parse v =
  match Semver.Version.parse v with
  | Ok v ->
    Format.printf "%a" Semver.Version.pp_inspect v
  | Error msg ->
    Format.printf "ERROR: %s" msg

let%expect_test _ =
  parse "1.1.1";
  [%expect {| 1.1.1 [] [] |}]

let%expect_test _ =
  parse "v1.1.1";
  [%expect {| 1.1.1 [] [] |}]

let%expect_test _ =
  parse "1.1.1-1";
  [%expect {| 1.1.1 [1] [] |}]

let%expect_test _ =
  parse "1.1.1-12.2";
  [%expect {| 1.1.1 [12;2] [] |}]

let%expect_test _ =
  parse "1.1.1+build";
  [%expect {| 1.1.1 [] [build] |}]

let%expect_test _ =
  parse "1.1.1+build.another";
  [%expect {| 1.1.1 [] [build;another] |}]

let%expect_test _ =
  parse "1.1.1-release+build";
  [%expect {| 1.1.1 [release] [build] |}]

let%expect_test _ =
  parse "1.1.1-rel-2020";
  [%expect {| 1.1.1 [rel-2020] [] |}]

let%expect_test _ =
  parse "1.1.1-rel-2020-05.12";
  [%expect {| 1.1.1 [rel-2020-05;12] [] |}]

let%expect_test _ =
  parse "1.1.1-rel-2020+build-2020";
  [%expect {| 1.1.1 [rel-2020] [build-2020] |}]

let%expect_test _ =
  parse "1.1.1-x";
  [%expect {| 1.1.1 [x] [] |}]

let%expect_test _ =
  parse "1.1.1-v";
  [%expect {| 1.1.1 [v] [] |}]

let%expect_test _ =
  parse "1.1.1-vx";
  [%expect {| 1.1.1 [vx] [] |}]

let%expect_test _ =
  parse "1.1.1--";
  [%expect {| 1.1.1 [-] [] |}]

let%expect_test _ =
  parse "1.1.1--+-";
  [%expect {| 1.1.1 [-] [-] |}]

let%expect_test _ =
  parse "1.1.1-X";
  [%expect {| 1.1.1 [X] [] |}]

let%expect_test _ =
  parse "1.1.1-X+x";
  [%expect {| 1.1.1 [X] [x] |}]

let%expect_test _ =
  parse "1.1.1-aX+bX";
  [%expect {| 1.1.1 [aX] [bX] |}]

let%expect_test _ =
  parse "1.1.1-Xa+Xb";
  [%expect {| 1.1.1 [Xa] [Xb] |}]

let%expect_test _ =
  parse "1.1.1-X+x.x";
  [%expect {| 1.1.1 [X] [x;x] |}]

