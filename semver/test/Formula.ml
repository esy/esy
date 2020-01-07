let%test_module "parse" = (module struct
  let parse_and_print v =
    match Semver.Formula.parse v with
    | Ok v ->
      Format.printf "%a" Semver.Formula.pp v
    | Error msg ->
      Format.printf "ERROR: %s" msg

  let%expect_test _ =
    parse_and_print "1.1.1";
    [%expect {| 1.1.1 |}]

  let%expect_test _ =
    parse_and_print " 1.1.1";
    [%expect {| 1.1.1 |}]

  let%expect_test _ =
    parse_and_print "1.1.1 ";
    [%expect {| 1.1.1 |}]

  let%expect_test _ =
    parse_and_print " 1.1.1 ";
    [%expect {| 1.1.1 |}]

  let%expect_test _ =
    parse_and_print "1.1";
    [%expect {| 1.1.x |}]

  let%expect_test _ =
    parse_and_print "1";
    [%expect {| 1.x.x |}]

  let%expect_test _ =
    parse_and_print "";
    [%expect {| * |}]

  let%expect_test _ =
    parse_and_print "x";
    [%expect {| * |}]

  let%expect_test _ =
    parse_and_print "X";
    [%expect {| * |}]

  let%expect_test _ =
    parse_and_print "*";
    [%expect {| * |}]

  let%expect_test _ =
    parse_and_print "=1.1.1";
    [%expect {| 1.1.1 |}]

  let%expect_test _ =
    parse_and_print "v1.1.1";
    [%expect {| 1.1.1 |}]

  let%expect_test _ =
    parse_and_print ">1.1.1";
    [%expect {| >1.1.1 |}]

  let%expect_test _ =
    parse_and_print ">v1.1.1";
    [%expect {| >1.1.1 |}]

  let%expect_test _ =
    parse_and_print ">=1.1.1";
    [%expect {| >=1.1.1 |}]

  let%expect_test _ =
    parse_and_print "<1.1.1";
    [%expect {| <1.1.1 |}]

  let%expect_test _ =
    parse_and_print "<=1.1.1";
    [%expect {| <=1.1.1 |}]

  let%expect_test _ =
    parse_and_print "<= 1.1.1";
    [%expect {| <=1.1.1 |}]

  let%expect_test _ =
    parse_and_print "^1.1.1";
    [%expect {| ^1.1.1 |}]

  let%expect_test _ =
    parse_and_print "~1.1.1";
    [%expect {| ~1.1.1 |}]

  let%expect_test _ =
    parse_and_print ">1.1";
    [%expect {| >1.1.x |}]

  let%expect_test _ =
    parse_and_print ">v1.1";
    [%expect {| >1.1.x |}]

  let%expect_test _ =
    parse_and_print "^1.1";
    [%expect {| ^1.1.x |}]

  let%expect_test _ =
    parse_and_print ">1";
    [%expect {| >1.x.x |}]

  let%expect_test _ =
    parse_and_print ">v1";
    [%expect {| >1.x.x |}]

  let%expect_test _ =
    parse_and_print "^1";
    [%expect {| ^1.x.x |}]

  let%expect_test _ =
    parse_and_print ">1.1.1 <2";
    [%expect {| >1.1.1 <2.x.x |}]

  let%expect_test _ =
    parse_and_print "1 || 2";
    [%expect {| 1.x.x || 2.x.x |}]

  let%expect_test _ =
    parse_and_print "v1 || 2";
    [%expect {| 1.x.x || 2.x.x |}]

  let%expect_test _ =
    parse_and_print "1|| 2";
    [%expect {| 1.x.x || 2.x.x |}]

  let%expect_test _ =
    parse_and_print "1 ||2";
    [%expect {| 1.x.x || 2.x.x |}]

  let%expect_test _ =
    parse_and_print "1||2";
    [%expect {| 1.x.x || 2.x.x |}]

  let%expect_test _ =
    parse_and_print "1 - 2";
    [%expect {| 1.x.x - 2.x.x |}]

  let%expect_test _ =
    parse_and_print "1 -  2";
    [%expect {| 1.x.x - 2.x.x |}]

  let%expect_test _ =
    parse_and_print "1  -  2";
    [%expect {| 1.x.x - 2.x.x |}]

  let%expect_test _ =
    parse_and_print "1  - 2";
    [%expect {| 1.x.x - 2.x.x |}]
end)

let%test_module "Formula.normalize" = (module struct
  let parse_and_normalize v =
    match Semver.Formula.parse v with
    | Ok f ->
      let f = Semver.Formula.normalize f in
      Format.printf "%a" Semver.Formula.N.pp f
    | Error msg ->
      Format.printf "ERROR: %s" msg

  (* hyphen ranges *)

  let%expect_test _ =
    parse_and_normalize "1.2.3 - 2.3.4";
    [%expect {| >=1.2.3 <=2.3.4 |}]

  let%expect_test _ =
    parse_and_normalize "1.2 - 2.3.4";
    [%expect {| >=1.2.0 <=2.3.4 |}]

  let%expect_test _ =
    parse_and_normalize "1.2.3 - 2.3";
    [%expect {| >=1.2.3 <2.4.0 |}]

  let%expect_test _ =
    parse_and_normalize "1.2.3 - 2";
    [%expect {| >=1.2.3 <3.0.0 |}]

  (* not documented at node-semver so we choose reasonable behaviour here *)
  let%expect_test _ =
    parse_and_normalize "1.2.3 - *";
    [%expect {| >=1.2.3 |}]

  (* not documented at node-semver so we choose reasonable behaviour here *)
  let%expect_test _ =
    parse_and_normalize "* - 1.2.3";
    [%expect {| <=1.2.3 |}]

  (* not documented at node-semver so we choose reasonable behaviour here *)
  let%expect_test _ =
    parse_and_normalize "* - *";
    [%expect {| >=0.0.0 |}]

  (* x-ranges *)

  let%expect_test _ =
    parse_and_normalize "*";
    [%expect {| >=0.0.0 |}]

  let%expect_test _ =
    parse_and_normalize "1.x";
    [%expect {| >=1.0.0 <2.0.0 |}]

  let%expect_test _ =
    parse_and_normalize "1.2.x";
    [%expect {| >=1.2.0 <1.3.0 |}]

  let%expect_test _ =
    parse_and_normalize "";
    [%expect {| >=0.0.0 |}]

  let%expect_test _ =
    parse_and_normalize "1";
    [%expect {| >=1.0.0 <2.0.0 |}]

  let%expect_test _ =
    parse_and_normalize "1.2";
    [%expect {| >=1.2.0 <1.3.0 |}]

  (* tilda ranges *)

  let%expect_test _ =
    parse_and_normalize "~1.2.3";
    [%expect {| >=1.2.3 <1.3.0 |}]

  let%expect_test _ =
    parse_and_normalize "~1.2";
    [%expect {| >=1.2.0 <1.3.0 |}]

  let%expect_test _ =
    parse_and_normalize "~1";
    [%expect {| >=1.0.0 <2.0.0 |}]

  let%expect_test _ =
    parse_and_normalize "~0.2.3";
    [%expect {| >=0.2.3 <0.3.0 |}]

  let%expect_test _ =
    parse_and_normalize "~0.2";
    [%expect {| >=0.2.0 <0.3.0 |}]

  let%expect_test _ =
    parse_and_normalize "~0";
    [%expect {| >=0.0.0 <1.0.0 |}]

  let%expect_test _ =
    parse_and_normalize "~1.2.3-beta.2";
    [%expect {| >=1.2.3-beta.2 <1.3.0 |}]

  (* caret ranges *)

  let%expect_test _ =
    parse_and_normalize "^1.2.3";
    [%expect {| >=1.2.3 <2.0.0 |}]

  let%expect_test _ =
    parse_and_normalize "^0.2.3";
    [%expect {| >=0.2.3 <0.3.0 |}]

  let%expect_test _ =
    parse_and_normalize "^0.0.3";
    [%expect {| >=0.0.3 <0.0.4 |}]

  let%expect_test _ =
    parse_and_normalize "^1.2.3-beta.2";
    [%expect {| >=1.2.3-beta.2 <2.0.0 |}]

  let%expect_test _ =
    parse_and_normalize "^0.0.3-beta";
    [%expect {| >=0.0.3-beta <0.0.4 |}]

  let%expect_test _ =
    parse_and_normalize "^1.2.x";
    [%expect {| >=1.2.0 <2.0.0 |}]

  let%expect_test _ =
    parse_and_normalize "^0.0.x";
    [%expect {| >=0.0.0 <0.1.0 |}]

  let%expect_test _ =
    parse_and_normalize "^0.0";
    [%expect {| >=0.0.0 <0.1.0 |}]

  let%expect_test _ =
    parse_and_normalize "^1.x";
    [%expect {| >=1.0.0 <2.0.0 |}]

  let%expect_test _ =
    parse_and_normalize "^0.x";
    [%expect {| >=0.0.0 <1.0.0 |}]

  let%expect_test _ =
    parse_and_normalize "^*";
    [%expect {| >=0.0.0 |}]
end)

let%test_module "Formula.satisfies" = (module struct
  let satisfies f v =
    let open Semver in
    let f = Formula.parse_exn f in
    let v = Version.parse_exn v in
    Formula.satisfies f v

  let%test _ = satisfies "1.0.0" "1.0.0"
  let%test _ = not @@ satisfies "1.0.0" "1.0.1"
  let%test _ = satisfies ">=1.0.0" "1.0.0"
  let%test _ = satisfies "<=1.0.0" "1.0.0"
  let%test _ = satisfies "<=1.0.0" "0.9.0"
  let%test _ = satisfies "<1.0.0" "0.9.0"
  let%test _ = not @@ satisfies "<=1.0.0" "1.1.0"
  let%test _ = not @@ satisfies "<1.0.0" "1.1.0"
  let%test _ = satisfies ">=1.0.0" "1.1.0"
  let%test _ = satisfies ">1.0.0" "1.1.0"
  let%test _ = not @@ satisfies ">=1.0.0" "0.9.0"
  let%test _ = not @@ satisfies ">1.0.0" "0.9.0"
  let%test _ = satisfies "1.0.0 - 1.1.0" "1.0.0"
  let%test _ = satisfies "1.0.0 - 1.1.0" "1.1.0"
  let%test _ = not @@ satisfies "1.0.0 - 1.1.0" "0.9.0"
  let%test _ = not @@ satisfies "1.0.0 - 1.1.0" "1.2.0"

  let%test _ = satisfies "~1.0.0" "1.0.0"
  let%test _ = not @@ satisfies "~1.0.0" "2.0.0"
  let%test _ = not @@ satisfies "~1.0.0" "0.9.0"
  let%test _ = not @@ satisfies "~1.0.0" "1.1.0"
  let%test _ = satisfies "~1.0.0" "1.0.1"
  let%test _ = satisfies "~0.3.0" "0.3.0"
  let%test _ = not @@ satisfies "~0.3.0" "0.4.0"
  let%test _ = not @@ satisfies "~0.3.0" "0.2.0"
  let%test _ = satisfies "~0.3.0" "0.3.1"

  let%test _ = satisfies "^1.0.0" "1.0.0"
  let%test _ = not @@ satisfies "^1.0.0" "2.0.0"
  let%test _ = not @@ satisfies "^1.0.0" "0.9.0"
  let%test _ = satisfies "^1.0.0" "1.1.0"
  let%test _ = satisfies "^1.0.0" "1.0.1"
  let%test _ = satisfies "^0.3.0" "0.3.0"
  let%test _ = not @@ satisfies "^0.3.0" "0.4.0"
  let%test _ = not @@ satisfies "^0.3.0" "0.2.0"
  let%test _ = satisfies "^0.3.0" "0.3.1"

  let%test _ = satisfies "1.0.0-alpha" "1.0.0-alpha"
  let%test _ = not @@ satisfies ">1.0.0" "1.0.0-alpha"
  let%test _ = not @@ satisfies ">=1.0.0" "1.0.0-alpha"
  let%test _ = not @@ satisfies "<1.0.0" "1.0.0-alpha"
  let%test _ = not @@ satisfies "<=1.0.0" "1.0.0-alpha"
  let%test _ = satisfies ">=1.0.0-alpha" "1.0.0-alpha"
  let%test _ = satisfies ">=1.0.0-alpha <2.0.0" "1.0.0-alpha"
  let%test _ = satisfies ">1.0.0-alpha.1 <2.0.0" "1.0.0-alpha.2"
  let%test _ = satisfies ">0.1.0 <=1.0.0-alpha" "1.0.0-alpha"
  let%test _ = satisfies ">0.1.0 <1.0.0-alpha.2" "1.0.0-alpha.1"
  let%test _ = satisfies "<=1.0.0-alpha" "1.0.0-alpha"
  let%test _ = satisfies ">=1.0.0-alpha.1" "1.0.0-alpha.2"
  let%test _ = satisfies ">1.0.0-alpha.1" "1.0.0-alpha.2"
  let%test _ = satisfies "<=1.0.0-alpha.2" "1.0.0-alpha.1"
  let%test _ = satisfies "<1.0.0-alpha.2" "1.0.0-alpha.1"
  let%test _ = not @@ satisfies ">=1.0.0 <3.0.0" "2.0.0-alpha"

  let%test _ = not @@ satisfies "1.0.0 - 2.0.0" "2.2.3"
  let%test _ = not @@ satisfies "1.2.3+asdf - 2.4.3+asdf" "1.2.3-pre.2"
  let%test _ = not @@ satisfies "1.2.3+asdf - 2.4.3+asdf" "2.4.3-alpha"
  let%test _ = not @@ satisfies "^1.2.3+build" "2.0.0"
  let%test _ = not @@ satisfies "^1.2.3+build" "1.2.0"
  let%test _ = not @@ satisfies "^1.2.3" "1.2.3-pre"
  let%test _ = not @@ satisfies "^1.2" "1.2.0-pre"
  let%test _ = not @@ satisfies ">1.2" "1.3.0-beta"
  let%test _ = not @@ satisfies "<=1.2.3" "1.2.3-beta"
  let%test _ = not @@ satisfies "^1.2.3" "1.2.3-beta"
  let%test _ = not @@ satisfies "=0.7.x" "0.7.0-asdf"
  let%test _ = not @@ satisfies ">=0.7.x" "0.7.0-asdf"
  let%test _ = not @@ satisfies "1" "1.0.0beta"
  let%test _ = not @@ satisfies "<1" "1.0.0beta"
  let%test _ = not @@ satisfies "< 1" "1.0.0beta"
  let%test _ = not @@ satisfies "1.0.0" "1.0.1"
  let%test _ = not @@ satisfies ">=1.0.0" "0.0.0"
  let%test _ = not @@ satisfies ">=1.0.0" "0.0.1"
  let%test _ = not @@ satisfies ">=1.0.0" "0.1.0"
  let%test _ = not @@ satisfies ">1.0.0" "0.0.1"
  let%test _ = not @@ satisfies ">1.0.0" "0.1.0"
  let%test _ = not @@ satisfies "<=2.0.0" "3.0.0"
  let%test _ = not @@ satisfies "<=2.0.0" "2.9999.9999"
  let%test _ = not @@ satisfies "<=2.0.0" "2.2.9"
  let%test _ = not @@ satisfies "<2.0.0" "2.9999.9999"
  let%test _ = not @@ satisfies "<2.0.0" "2.2.9"
  let%test _ = not @@ satisfies ">=0.1.97" "v0.1.93"
  let%test _ = not @@ satisfies ">=0.1.97" "0.1.93"
  let%test _ = not @@ satisfies "0.1.20 || 1.2.4" "1.2.3"
  let%test _ = not @@ satisfies ">=0.2.3 || <0.0.1" "0.0.3"
  let%test _ = not @@ satisfies ">=0.2.3 || <0.0.1" "0.2.2"
  let%test _ = not @@ satisfies "2.x.x" "1.1.3"
  let%test _ = not @@ satisfies "2.x.x" "3.1.3"
  let%test _ = not @@ satisfies "1.2.x" "1.3.3"
  let%test _ = not @@ satisfies "1.2.x || 2.x" "3.1.3"
  let%test _ = not @@ satisfies "1.2.x || 2.x" "1.1.3"
  let%test _ = not @@ satisfies "2.*.*" "1.1.3"
  let%test _ = not @@ satisfies "2.*.*" "3.1.3"
  let%test _ = not @@ satisfies "1.2.*" "1.3.3"
  let%test _ = not @@ satisfies "1.2.* || 2.*" "3.1.3"
  let%test _ = not @@ satisfies "1.2.* || 2.*" "1.1.3"
  let%test _ = not @@ satisfies "2" "1.1.2"
  let%test _ = not @@ satisfies "2.3" "2.4.1"
  let%test _ = not @@ satisfies "~0.0.1" "0.1.0-alpha"
  let%test _ = not @@ satisfies "~0.0.1" "0.1.0"
  let%test _ = not @@ satisfies "~2.4" "2.5.0"
  let%test _ = not @@ satisfies "~2.4" "2.3.9"
  let%test _ = not @@ satisfies "~>3.2.1" "3.3.2"
  let%test _ = not @@ satisfies "~>3.2.1" "3.2.0"
  let%test _ = not @@ satisfies "~1" "0.2.3"
  let%test _ = not @@ satisfies "~>1" "2.2.3"
  let%test _ = not @@ satisfies "~1.0" "1.1.0"
  let%test _ = not @@ satisfies "<1" "1.0.0"
  let%test _ = not @@ satisfies ">=1.2" "1.1.1"
  let%test _ = not @@ satisfies "1" "2.0.0beta"
  let%test _ = not @@ satisfies "~v0.5.4-beta" "0.5.4-alpha"
  let%test _ = not @@ satisfies "=0.7.x" "0.8.2"
  let%test _ = not @@ satisfies ">=0.7.x" "0.6.2"
  let%test _ = not @@ satisfies "<0.7.x" "0.7.2"
  let%test _ = not @@ satisfies "<1.2.3" "1.2.3-beta"
  let%test _ = not @@ satisfies "=1.2.3" "1.2.3-beta"
  let%test _ = not @@ satisfies ">1.2" "1.2.8"
  let%test _ = not @@ satisfies "^0.0.1" "0.0.2-alpha"
  let%test _ = not @@ satisfies "^0.0.1" "0.0.2"
  let%test _ = not @@ satisfies "^1.2.3" "2.0.0-alpha"
  let%test _ = not @@ satisfies "^1.2.3" "1.2.2"
  let%test _ = not @@ satisfies "^1.2" "1.1.9"
  let%test _ = not @@ satisfies "*" "v1.2.3-foo"

  let%test _ = not @@ satisfies "2.x" "3.0.0-pre.0"
  let%test _ = not @@ satisfies "^1.0.0" "1.0.0-rc1"
  let%test _ = not @@ satisfies "^1.2.3-rc2" "2.0.0"

  let%test _ = satisfies "1.2.3-beta+build" " = 1.2.3-beta+otherbuild"
  let%test _ = satisfies "1.2.3+build" " = 1.2.3+otherbuild"
  let%test _ = satisfies "1.2.3-beta+build" "1.2.3-beta+otherbuild"
  let%test _ = satisfies "1.2.3+build" "1.2.3+otherbuild"
  let%test _ = satisfies "  v1.2.3+build" "1.2.3+otherbuild"
  let%test _ = satisfies ">=v1.2.3+build" "1.2.3+otherbuild"
  let%test _ = satisfies "<=v1.2.3+build" "1.2.3+otherbuild"
end)
