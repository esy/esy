module String = Astring.String

type t =
  segment list * string
  [@@deriving ord]

and segment =
  | Pkg of string
  | AnyPkg

let show (path, pkg) =
  match path with
  | [] -> pkg
  | path ->
  let path =
    path
    |> List.map ~f:(function | Pkg name -> name | AnyPkg -> "**")
    |> String.concat ~sep:"/"
  in path ^ "/" ^ pkg

let pp fmt v = Fmt.pf fmt "%s" (show v)

let parse v =
  let parts = String.cuts ~empty:true ~sep:(("/")[@reason.raw_literal "/"]) v in
  let f (parts, scope) segment =
    match segment with
    | "" -> Error ("invalid package path: " ^ v)
    | segment ->
        match segment.[0], segment, scope with
        | '@', _, None -> Ok (parts, Some segment)
        | '@', _, Some _ -> Error ("invalid package path: " ^ v)
        | _, "**", None -> Ok (AnyPkg::parts, None)
        | _, _, None -> Ok ((Pkg segment)::parts, None)
        | _, "**", Some _ -> Error ("invalid package path: " ^ v)
        | _, _, Some scope ->
          let pkg = scope ^ "/" ^ segment in
          Ok ((Pkg pkg)::parts, None)
  in
  match Result.List.foldLeft ~f ~init:([], None) parts with
  | Error err -> Error err
  | Ok ([], None)
  | Ok (_, Some _)
  | Ok (AnyPkg::_, None) -> Error ("invalid package path: " ^ v)
  | Ok ((Pkg pkg)::path, None) -> Ok ((List.rev path, pkg))

let%test_module _ = (module struct
  let raiseNotExpected p =
    let msg = Printf.sprintf "Not expected: [%s]" (show p) in
    raise (Failure msg)

  let parsesOkTo v e =
    match parse v with
    | Ok p when p = e -> ()
    | Ok p -> raiseNotExpected p
    | Error err -> raise (Failure err)

  let parsesToErr v =
    match parse v with
    | Ok p -> raiseNotExpected p
    | Error _err -> ()

    let%test_unit _ = parsesOkTo "some" ([], "some")
    let%test_unit _ = parsesOkTo "some/another" ([Pkg "some"], "another")
    let%test_unit _ = parsesOkTo "**/another" ([AnyPkg], "another")
    let%test_unit _ = parsesOkTo "@scp/pkg" ([], "@scp/pkg")
    let%test_unit _ = parsesOkTo "@scp/pkg/another" ([Pkg "@scp/pkg"], "another")
    let%test_unit _ = parsesOkTo "@scp/pkg/**/hey" ([Pkg "@scp/pkg"; AnyPkg], "hey")
    let%test_unit _ = parsesOkTo "another/@scp/pkg" ([Pkg "another"], "@scp/pkg")
    let%test_unit _ = parsesOkTo "another/**/@scp/pkg" ([Pkg "another"; AnyPkg], "@scp/pkg")
    let%test_unit _ = parsesOkTo "@scp/pkg/@scp/another" ([Pkg "@scp/pkg"], "@scp/another")
    let%test_unit _ = parsesOkTo "@scp/pkg/**/@scp/another" ([Pkg "@scp/pkg"; AnyPkg], "@scp/another")

    let%test_unit _ = parsesToErr "@some"
    let%test_unit _ = parsesToErr "**"
    let%test_unit _ = parsesToErr "@some/"
    let%test_unit _ = parsesToErr "@some/**"
    let%test_unit _ = parsesToErr "@scp/pkg/**"
    let%test_unit _ = parsesToErr "@some//"
    let%test_unit _ = parsesToErr "@some//pkg"
    let%test_unit _ = parsesToErr "pkg1//pkg2"
    let%test_unit _ = parsesToErr "pkg1/"
    let%test_unit _ = parsesToErr "/pkg1"
end)


let to_yojson v = `String (show v)
let of_yojson = function
  | `String v -> parse v
  | _ -> Error "expected string"
