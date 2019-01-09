module String = Astring.String;

[@deriving ord]
type t = (list(segment), string)
and segment =
  | Pkg(string)
  | AnyPkg;

let show = ((path, pkg)) =>
  switch (path) {
  | [] => pkg
  | path =>
    let path =
      path
      |> List.map(
           ~f=
             fun
             | Pkg(name) => name
             | AnyPkg => "**",
         )
      |> String.concat(~sep="/");
    path ++ "/" ++ pkg;
  };

let pp = (fmt, v) => Fmt.pf(fmt, "%s", show(v));

let parse = v => {
  let parts = String.cuts(~empty=true, ~sep="/", v);
  let f = ((parts, scope), segment) =>
    switch (segment) {
    | "" => Error("invalid package path: " ++ v)
    | segment =>
      switch (segment.[0], segment, scope) {
      | ('@', _, None) => [@implicit_arity] Ok(parts, Some(segment))
      | ('@', _, Some(_)) => Error("invalid package path: " ++ v)
      | (_, "**", None) => [@implicit_arity] Ok([AnyPkg, ...parts], None)
      | (_, _, None) =>
        [@implicit_arity] Ok([Pkg(segment), ...parts], None)
      | (_, "**", Some(_)) => Error("invalid package path: " ++ v)
      | (_, _, Some(scope)) =>
        let pkg = scope ++ "/" ++ segment;
        [@implicit_arity] Ok([Pkg(pkg), ...parts], None);
      }
    };

  switch (Result.List.foldLeft(~f, ~init=([], None), parts)) {
  | Error(err) => Error(err)
  | [@implicit_arity] Ok([], None)
  | [@implicit_arity] Ok(_, Some(_))
  | [@implicit_arity] Ok([AnyPkg, ..._], None) =>
    Error("invalid package path: " ++ v)
  | [@implicit_arity] Ok([Pkg(pkg), ...path], None) =>
    [@implicit_arity] Ok(List.rev(path), pkg)
  };
};

let%test_module _ =
  (module
   {
     let raiseNotExpected = p => {
       let msg = Printf.sprintf("Not expected: [%s]", show(p));
       raise(Failure(msg));
     };

     let parsesOkTo = (v, e) =>
       switch (parse(v)) {
       | Ok(p) when p == e => ()
       | Ok(p) => raiseNotExpected(p)
       | Error(err) => raise(Failure(err))
       };

     let parsesToErr = v =>
       switch (parse(v)) {
       | Ok(p) => raiseNotExpected(p)
       | Error(_err) => ()
       };

     let%test_unit _ = parsesOkTo("some", ([], "some"));
     let%test_unit _ =
       parsesOkTo("some/another", ([Pkg("some")], "another"));
     let%test_unit _ = parsesOkTo("**/another", ([AnyPkg], "another"));
     let%test_unit _ = parsesOkTo("@scp/pkg", ([], "@scp/pkg"));
     let%test_unit _ =
       parsesOkTo("@scp/pkg/another", ([Pkg("@scp/pkg")], "another"));
     let%test_unit _ =
       parsesOkTo("@scp/pkg/**/hey", ([Pkg("@scp/pkg"), AnyPkg], "hey"));
     let%test_unit _ =
       parsesOkTo("another/@scp/pkg", ([Pkg("another")], "@scp/pkg"));
     let%test_unit _ =
       parsesOkTo(
         "another/**/@scp/pkg",
         ([Pkg("another"), AnyPkg], "@scp/pkg"),
       );
     let%test_unit _ =
       parsesOkTo(
         "@scp/pkg/@scp/another",
         ([Pkg("@scp/pkg")], "@scp/another"),
       );
     let%test_unit _ =
       parsesOkTo(
         "@scp/pkg/**/@scp/another",
         ([Pkg("@scp/pkg"), AnyPkg], "@scp/another"),
       );

     let%test_unit _ = parsesToErr("@some");
     let%test_unit _ = parsesToErr("**");
     let%test_unit _ = parsesToErr("@some/");
     let%test_unit _ = parsesToErr("@some/**");
     let%test_unit _ = parsesToErr("@scp/pkg/**");
     let%test_unit _ = parsesToErr("@some//");
     let%test_unit _ = parsesToErr("@some//pkg");
     let%test_unit _ = parsesToErr("pkg1//pkg2");
     let%test_unit _ = parsesToErr("pkg1/");
     let%test_unit _ = parsesToErr("/pkg1");
   });

let to_yojson = v => `String(show(v));
let of_yojson =
  fun
  | `String(v) => parse(v)
  | _ => Error("expected string");
