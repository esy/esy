module Source = Package.Source
module SourceSpec = Package.SourceSpec
module String = Astring.String

module OpamPathsByVersion = Memoize.Make(struct
  type key = OpamPackage.Name.t
  type value = Path.t OpamPackage.Version.Map.t RunAsync.t
end)

type t = {
  repoPath : Path.t;
  (* overrides : OpamOverrides.t; *)
  pathsCache : OpamPathsByVersion.t;
}

type resolution = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  opam: Path.t;
  url: Path.t option;
}

module Manifest = struct
  type t = {
    name: OpamPackage.Name.t;
    version: OpamPackage.Version.t;
    opam: OpamFile.OPAM.t;
    url: OpamFile.URL.t option;
  }

  let ofFile ~name ~version ?url opam =
    let open RunAsync.Syntax in
    let%bind opam =
      let%bind data = Fs.readFile opam in
      return (OpamFile.OPAM.read_from_string data)
    in
    let%bind url =
      match url with
      | Some url ->
        let%bind data = Fs.readFile url in
        return (Some (OpamFile.URL.read_from_string data))
      | None -> return None
    in
    return {name; version; opam; url;}

  let toPackage ~name ~version {name = _; version = _; opam; url} =
    let open RunAsync.Syntax in
    let%bind source =
      match url with
      | Some url ->
        let {OpamUrl. backend; path; hash; _} = OpamFile.URL.url url in
        begin match backend, hash with
        | `http, Some hash ->
          return (Package.Source (Package.Source.Archive (path, hash)))
        | `http, None ->
          (* TODO: what to do here? fail or resolve? *)
          return (Package.SourceSpec (Package.SourceSpec.Archive (path, None)))
        | `rsync, _ -> error "unsupported source for opam: rsync"
        | `hg, _ -> error "unsupported source for opam: hg"
        | `darcs, _ -> error "unsupported source for opam: darcs"
        | `git, ref ->
          return (Package.SourceSpec (Package.SourceSpec.Git {remote = path; ref}))
        end
      | None -> return (Package.Source Package.Source.NoSource)
    in

    let translateFormula f =
      let translateAtom ((name, relop) : OpamFormula.atom) =
        let module C = OpamVersion.Constraint in
        let name = "@opam/" ^ OpamPackage.Name.to_string name in
        let req =
          match relop with
          | None -> C.ANY
          | Some (`Eq, v) -> C.EQ v
          | Some (`Neq, v) -> C.NEQ v
          | Some (`Lt, v) -> C.LT v
          | Some (`Gt, v) -> C.GT v
          | Some (`Leq, v) -> C.LTE v
          | Some (`Geq, v) -> C.GTE v
        in {Package.Dep. name; req = Opam req}
      in
      let cnf = OpamFormula.to_cnf f in
      List.map ~f:(List.map ~f:translateAtom) cnf
    in

    let dependencies =
      let f =
        OpamFilter.filter_deps
          ~build:true ~post:true ~test:false ~doc:false ~dev:false
          (OpamFile.OPAM.depends opam)
      in translateFormula f
    in

    let devDependencies =
      let f =
        OpamFilter.filter_deps
          ~build:false ~post:false ~test:true ~doc:true ~dev:true
          (OpamFile.OPAM.depends opam)
      in translateFormula f
    in

    return {
      Package.
      name;
      version;
      kind = Package.Esy;
      source;
      opam = None; (* TODO: *)
      dependencies;
      devDependencies;
    }
end

let init ~cfg () =
  let open RunAsync.Syntax in
  let%bind repoPath =
    match cfg.Config.opamRepository with
    | Config.Local local -> return local
    | Config.Remote (remote, local) ->
      let%bind () = Git.ShallowClone.update ~branch:"master" ~dst:local remote in
      return local
  in

  (* and overrides = OpamOverrides.init ~cfg () in *)

  return {
    repoPath;
    pathsCache = OpamPathsByVersion.make ();
    (* overrides; *)
  }

let getVersionIndex registry ~(name : OpamPackage.Name.t) =
  let f name =
    let open RunAsync.Syntax in
    let path = Path.(
      registry.repoPath
      / "packages"
      / OpamPackage.Name.to_string name
    ) in
    let%bind entries = Fs.listDir path in
    let f index entry =
      let version = match String.cut ~sep:"." entry with
        | None -> OpamPackage.Version.of_string ""
        | Some (_name, version) -> OpamPackage.Version.of_string version
      in
      OpamPackage.Version.Map.add version Path.(path / entry) index
    in
    return (List.fold_left ~init:OpamPackage.Version.Map.empty ~f entries)
  in
  OpamPathsByVersion.compute registry.pathsCache name f

let getPackage registry ~(name : OpamPackage.Name.t) ~(version : OpamPackage.Version.t) =
  let open RunAsync.Syntax in
  let%bind index = getVersionIndex registry ~name in
  match OpamPackage.Version.Map.find_opt version index with
  | None -> return None
  | Some packagePath ->
    (* TODO: load & parse manifets, then check available flag here *)
    let opam = Path.(packagePath / "opam") in
    let%bind url =
      let url = Path.(packagePath / "url") in
      if%bind Fs.exists url
      then return (Some url)
      else return None
    in
    return (Some {
      name;
      opam;
      url;
      version
    })

let versions registry ~(name : OpamPackage.Name.t) =
  let open RunAsync.Syntax in
  let%bind index = getVersionIndex registry ~name in
  let%bind items =
    index
    |> OpamPackage.Version.Map.bindings
    |> List.map ~f:(fun (version, _path) -> getPackage registry ~name ~version)
    |> RunAsync.List.joinAll
  in
  return (List.filterNone items)

let version registry ~(name : OpamPackage.Name.t) ~version =
  let open RunAsync.Syntax in
  match%bind getPackage registry ~name ~version with
  | None -> return None
  | Some { opam; url; name; version } ->
    let%bind pkg = Manifest.ofFile ~name ~version ?url opam
    (* TODO: apply overrides *)
    (* begin match%bind OpamOverrides.get registry.overrides name version with *)
    (*   | None -> *)
    (*     return (Some manifest) *)
    (*   | Some override -> *)
    (*     let manifest = OpamOverrides.apply manifest override in *)
    (*     return (Some manifest) *)
    (* end *)
    in
    return (Some pkg)
