type 'sandbox project = {
  path : Path.t;
  sandbox : 'sandbox;
  sandboxByName : 'sandbox StringMap.t;
}

type t = sandbox project

and sandbox =
  | Esy of {path : Path.t; name : string option}
  | Opam of {path : Path.t}
  | AggregatedOpam of {paths : Path.t list}

let ofDir path =
  let open RunAsync.Syntax in

  let isOpam path = Path.hasExt ".opam" path || Path.basename path = "opam" in
  let isEsyJson path = Path.basename path = "esy.json" in
  let isPackageJson path = Path.basename path = "package.json" in

  let isNamedPackageJson =
    let re =
      Re.(seq [bos; str "package."; group (rep1 alnum); str ".json"; eos] |> compile)
    in
    let check path =
      let name = Path.basename path in
      match Re.exec_opt re name with
      | None -> None
      | Some m -> Some (Re.get m 1)
    in
    check
  in

  let%bind items =
    let%bind names = Fs.listDir path in
    return (List.map ~f:(fun name -> Path.(path / name)) names)
  in

  let packageJson, esyJson, opam, sandboxByName =
    let packageJson, esyJson, opam, sandboxByName =
      let f (packageJson, esyJson, opam, sandboxByName) path =
        if isPackageJson path
        then (Some (Esy {path; name = None;}), esyJson, opam, sandboxByName)
        else if isEsyJson path
        then (packageJson, Some (Esy {path; name = None}), opam, sandboxByName)
        else if isOpam path
        then (packageJson, esyJson, path::opam, sandboxByName)
        else
          match isNamedPackageJson path with
          | Some name ->
            let sandboxByName =
              let sandbox = Esy {path; name = Some name;} in
              StringMap.add name sandbox sandboxByName
            in
            (packageJson, esyJson, opam, sandboxByName)
          | None -> (packageJson, esyJson, opam, sandboxByName)
      in
      List.fold_left ~f ~init:(None, None, [], StringMap.empty) items
    in
    let opam =
      match opam with
      | [] -> None
      | [path] -> Some (Opam {path})
      | paths -> Some (AggregatedOpam {paths})
    in
    packageJson, esyJson, opam, sandboxByName
  in

  let sandbox =
    Option.orOther esyJson ~other:(Option.orOther packageJson ~other:opam)
  in

  match sandbox, StringMap.is_empty sandboxByName with
  | None, true -> return None
  | None, false -> return None
  | Some sandbox, _ -> return (Some {path; sandbox; sandboxByName;})

let initWith f project =
  let open RunAsync.Syntax in
  let%bind sandbox =
    let%bind sandbox = f project.sandbox in
    return sandbox
  in
  let%bind sandboxByName =
    let f name sandbox map =
      let%bind map = map in
      let%bind sandbox = f sandbox in
      let map = StringMap.add name sandbox map in
      return map
    in
    StringMap.fold f project.sandboxByName (return StringMap.empty)
  in
  return {sandbox; sandboxByName; path = project.path}

let forEach f project =
  let open RunAsync.Syntax in
  let%bind () = f None project.sandbox in
  let%bind () =
    let f name sandbox prev =
      let%bind () = prev in
      f (Some name) sandbox
    in
    StringMap.fold f project.sandboxByName (return ())
  in
  return ()
