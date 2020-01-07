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

let%expect_test _ =
  parse "1.1.1beta";
  [%expect {| 1.1.1 [beta] [] |}]

let%test_module "Version.compare" = (module struct

  (* for each of those cases (a, b) holds a > b *)
  let cases_gt = [
    "0.0.0", "0.0.0-foo";
    "0.0.1", "0.0.0";
    "1.0.0", "0.9.9";
    "0.10.0", "0.9.0";
    "0.99.0", "0.10.0";
    "2.0.0", "1.2.3";
    "v0.0.0", "0.0.0-foo";
    "v0.0.1", "0.0.0";
    "v1.0.0", "0.9.9";
    "v0.10.0", "0.9.0";
    "v0.99.0", "0.10.0";
    "v2.0.0", "1.2.3";
    "0.0.0", "v0.0.0-foo";
    "0.0.1", "v0.0.0";
    "1.0.0", "v0.9.9";
    "0.10.0", "v0.9.0";
    "0.99.0", "v0.10.0";
    "2.0.0", "v1.2.3";
    "1.2.3", "1.2.3-asdf";
    "1.2.3", "1.2.3-4";
    "1.2.3", "1.2.3-4-foo";
    "1.2.3-5-foo", "1.2.3-5";
    "1.2.3-5", "1.2.3-4";
    "1.2.3-5-foo", "1.2.3-5-Foo";
    "3.0.0", "2.7.2+asdf";
    "1.2.3-a.10", "1.2.3-a.5";
    "1.2.3-a.b", "1.2.3-a.5";
    "1.2.3-a.b", "1.2.3-a";
    "1.2.3-a.b.c.10.d.5", "1.2.3-a.b.c.5.d.100";
    "1.2.3-r2", "1.2.3-r100";
    "1.2.3-r100", "1.2.3-R2";
  ]

  let%test _ =
    ListLabels.for_all cases_gt ~f:(fun (a, b) ->
      let a = Semver.Version.parse_exn a in
      let b = Semver.Version.parse_exn b in
      Semver.Version.compare a b = 1)

  let cases_eq = [
    "1.2.3", "v1.2.3";
    "1.2.3", "=1.2.3";
    "1.2.3", "v 1.2.3";
    "1.2.3", "= 1.2.3";
    "1.2.3", " v1.2.3";
    "1.2.3", " =1.2.3";
    "1.2.3", " v 1.2.3";
    "1.2.3", " = 1.2.3";
    "1.2.3-0", "v1.2.3-0";
    "1.2.3-0", "=1.2.3-0";
    "1.2.3-0", "v 1.2.3-0";
    "1.2.3-0", "= 1.2.3-0";
    "1.2.3-0", " v1.2.3-0";
    "1.2.3-0", " =1.2.3-0";
    "1.2.3-0", " v 1.2.3-0";
    "1.2.3-0", " = 1.2.3-0";
    "1.2.3-1", "v1.2.3-1";
    "1.2.3-1", "=1.2.3-1";
    "1.2.3-1", "v 1.2.3-1";
    "1.2.3-1", "= 1.2.3-1";
    "1.2.3-1", " v1.2.3-1";
    "1.2.3-1", " =1.2.3-1";
    "1.2.3-1", " v 1.2.3-1";
    "1.2.3-1", " = 1.2.3-1";
    "1.2.3-beta", "v1.2.3-beta";
    "1.2.3-beta", "=1.2.3-beta";
    "1.2.3-beta", "v 1.2.3-beta";
    "1.2.3-beta", "= 1.2.3-beta";
    "1.2.3-beta", " v1.2.3-beta";
    "1.2.3-beta", " =1.2.3-beta";
    "1.2.3-beta", " v 1.2.3-beta";
    "1.2.3-beta", " = 1.2.3-beta";
    (* those are valid in original npm but we choose to compare build as well *)
    (* "1.2.3-beta+build", " = 1.2.3-beta+otherbuild"; *)
    (* "1.2.3+build", " = 1.2.3+otherbuild"; *)
    (* "1.2.3-beta+build", "1.2.3-beta+otherbuild"; *)
    (* "1.2.3+build", "1.2.3+otherbuild"; *)
    (* "  v1.2.3+build", "1.2.3+otherbuild"; *)
  ]

  let%test _ =
    ListLabels.for_all cases_eq ~f:(fun (a, b) ->
      let a = Semver.Version.parse_exn a in
      let b = Semver.Version.parse_exn b in
      Semver.Version.compare a b = 0)

end)
