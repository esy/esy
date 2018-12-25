open EsyPackageConfig

let esySubstsDep = {
  Package.Dep.
  name = "@esy-ocaml/substs";
  req = Npm SemverVersion.Constraint.ANY;
}

module File = struct
  module Cache = Memoize.Make(struct
    type key = Path.t
    type value = OpamFile.OPAM.t RunAsync.t
  end)

  let ofString ?upgradeIfOpamVersionIsLessThan ?filename data =
    let filename =
      let filename = Option.orDefault ~default:"opam" filename in
      OpamFile.make (OpamFilename.of_string filename)
    in
    let opam = OpamFile.OPAM.read_from_string ~filename data in
    match upgradeIfOpamVersionIsLessThan with
    | Some upgradeIfOpamVersionIsLessThan ->
      let opamVersion = OpamFile.OPAM.opam_version opam in
      if OpamVersion.compare opamVersion upgradeIfOpamVersionIsLessThan < 0
      then OpamFormatUpgrade.opam_file ~filename opam
      else opam
    | None -> opam

  let ofPath ?upgradeIfOpamVersionIsLessThan ?cache path =
    let open RunAsync.Syntax in
    let load () =
      let%bind data = Fs.readFile path in
      let filename = Path.show path in
      return (ofString ?upgradeIfOpamVersionIsLessThan ~filename data)
    in
    match cache with
    | Some cache -> Cache.compute cache path load
    | None -> load ()
end

type t = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  opam: OpamFile.OPAM.t;
  url: OpamFile.URL.t option;
  override : Override.t option;
  opamRepositoryPath : Path.t option;
}

let ofPath ~name ~version (path : Path.t) =
  let open RunAsync.Syntax in
  let%bind opam = File.ofPath path in
  return {
    name;
    version;
    opamRepositoryPath = Some (Path.parent path);
    opam;
    url = None;
    override = None;
  }

let ofString ~name ~version (data : string) =
  let open Run.Syntax in
  let opam = File.ofString data in
  return {
    name;
    version;
    opam;
    url = None;
    opamRepositoryPath = None;
    override = None;
  }

let ocamlOpamVersionToOcamlNpmVersion v =
  let v = OpamPackage.Version.to_string v in
  SemverVersion.Version.parse v

let convertOpamAtom ((name, relop) : OpamFormula.atom) =
  let open Result.Syntax in
  let name =
    match OpamPackage.Name.to_string name with
    | "ocaml" -> "ocaml"
    | name -> "@opam/" ^ name
  in
  match name with
  | "ocaml" ->
    let module C = SemverVersion.Constraint in
    let%bind req =
      match relop with
      | None -> return C.ANY
      | Some (`Eq, v) ->
        begin match OpamPackage.Version.to_string v with
        | "broken" -> error "package is marked as broken"
        | _ ->
          let%bind v = ocamlOpamVersionToOcamlNpmVersion v in
          return (C.EQ v)
        end
      | Some (`Neq, v) ->
        let%bind v = ocamlOpamVersionToOcamlNpmVersion v in return (C.NEQ v)
      | Some (`Lt, v) ->
        let%bind v = ocamlOpamVersionToOcamlNpmVersion v in return (C.LT v)
      | Some (`Gt, v) ->
        let%bind v = ocamlOpamVersionToOcamlNpmVersion v in return (C.GT v)
      | Some (`Leq, v) ->
        let%bind v = ocamlOpamVersionToOcamlNpmVersion v in return (C.LTE v)
      | Some (`Geq, v) ->
        let%bind v = ocamlOpamVersionToOcamlNpmVersion v in return (C.GTE v)
    in
    return {Package.Dep. name; req = Npm req}
  | name ->
    let module C = OpamPackageVersion.Constraint in
    let req =
      match relop with
      | None -> C.ANY
      | Some (`Eq, v) -> C.EQ v
      | Some (`Neq, v) -> C.NEQ v
      | Some (`Lt, v) -> C.LT v
      | Some (`Gt, v) -> C.GT v
      | Some (`Leq, v) -> C.LTE v
      | Some (`Geq, v) -> C.GTE v
    in
    return {Package.Dep. name; req = Opam req}

let convertOpamFormula f =
  let cnf = OpamFormula.to_cnf f in
  Result.List.map ~f:(Result.List.map ~f:convertOpamAtom) cnf

let convertOpamUrl (manifest : t) =
  let open Result.Syntax in

  let convChecksum hash =
    match OpamHash.kind hash with
    | `MD5 -> Checksum.Md5, OpamHash.contents hash
    | `SHA256 -> Checksum.Sha256, OpamHash.contents hash
    | `SHA512 -> Checksum.Sha512, OpamHash.contents hash
  in

  let convUrl (url : OpamUrl.t) =
    match url.backend with
    | `http -> return (OpamUrl.to_string url)
    | _ -> errorf "unsupported dist for opam package: %s" (OpamUrl.to_string url)
  in

  let sourceOfOpamUrl url =

    let%bind hash =
      match OpamFile.URL.checksum url with
      | [] ->
        errorf
          "no checksum provided for %s@%s"
          (OpamPackage.Name.to_string manifest.name)
          (OpamPackage.Version.to_string manifest.version)
      | hash::_ -> return hash
    in

    let mirrors =
      let urls =
        (OpamFile.URL.url url)
        ::(OpamFile.URL.mirrors url)
      in
      let f mirrors url =
        match convUrl url with
        | Ok url -> Dist.Archive {url; checksum = convChecksum hash;}::mirrors
        | Error _ -> mirrors
      in
      List.fold_left ~f ~init:[] urls
    in

    let main =
      let url = "https://opam.ocaml.org/cache/" ^ String.concat "/" (OpamHash.to_path hash) in
      Dist.Archive {url; checksum = convChecksum hash;}
    in

    return (main, mirrors)
  in

  match manifest.url with
  | Some url -> sourceOfOpamUrl url
  | None ->
    let main = Dist.NoSource in
    Ok (main, [])

let convertDependencies manifest =
  let open Result.Syntax in

  let filterOpamFormula ~build ~post ~test ~doc ~dev f =
    let f =
      let env var =
        match OpamVariable.Full.to_string var with
        | "test" -> Some (OpamVariable.B test)
        | "doc" -> Some (OpamVariable.B doc)
        | _ -> None
      in
      OpamFilter.partial_filter_formula env f
    in
    try return (OpamFilter.filter_deps ~default:true ~build ~post ~test ~doc ~dev f)
    with Failure msg -> Error msg
  in

  let filterAndConvertOpamFormula ~build ~post ~test ~doc ~dev f =
    let%bind f = filterOpamFormula ~build ~post ~test ~doc ~dev f in
    convertOpamFormula f
  in

  let%bind dependencies =
    let%bind formula =
      filterAndConvertOpamFormula
        ~build:true ~post:true ~test:false ~doc:false ~dev:false
        (OpamFile.OPAM.depends manifest.opam)
    in
    let formula =
      formula
      @ [
          [esySubstsDep];
        ]
    in
    return (Package.Dependencies.OpamFormula formula)
  in

  let%bind devDependencies =
    let%bind formula =
      filterAndConvertOpamFormula
        ~build:false ~post:false ~test:true ~doc:true ~dev:true
        (OpamFile.OPAM.depends manifest.opam)
    in return (Package.Dependencies.OpamFormula formula)
  in

  let%bind optDependencies =
    let%bind formula =
      filterOpamFormula
        ~build:false ~post:false ~test:true ~doc:true ~dev:true
        (OpamFile.OPAM.depopts manifest.opam)
    in
    return (
      formula
      |> OpamFormula.atoms
      |> List.map ~f:(fun (name, _) -> "@opam/" ^ OpamPackage.Name.to_string name)
      |> StringSet.of_list
    )
  in

  return (dependencies, devDependencies, optDependencies)

let toPackage ?source ~name ~version manifest =
  let open RunAsync.Syntax in

  let converted =
    let open Result.Syntax in
    let%bind source = convertOpamUrl manifest in
    let%bind dependencies, devDependencies, optDependencies = convertDependencies manifest in
    return (source, dependencies, devDependencies, optDependencies)
  in

  match converted with
  | Error err -> return (Error err)
  | Ok (sourceFromOpam, dependencies, devDependencies, optDependencies) ->

    let opam =
      match manifest.opamRepositoryPath with
      | Some path -> Some (
          OpamResolution.make
            manifest.name
            manifest.version
            path)
      | None -> None
    in

    let source =
      match source with
      | None ->
        PackageSource.Install {source = sourceFromOpam; opam;}
      | Some (Source.Link {path; manifest;}) ->
        Link {path; manifest;}
      | Some (Source.Dist source) ->
        Install {source = source, []; opam;}
    in

    let overrides =
      match manifest.override with
      | None -> Overrides.empty
      | Some override -> Overrides.(add override empty)
    in

    return (Ok {
      Package.
      name;
      version;
      originalVersion = None;
      originalName = None;
      kind = Package.Esy;
      source;
      overrides;
      dependencies;
      devDependencies;
      optDependencies;
      peerDependencies = PackageConfig.NpmFormula.empty;
      resolutions = PackageConfig.Resolutions.empty;
    })
