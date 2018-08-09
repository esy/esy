module Override = Package.OpamOverride

module File = struct
  module Cache = Memoize.Make(struct
    type key = Path.t
    type value = OpamFile.OPAM.t RunAsync.t
  end)

  let ofPath ?cache path =
    let open RunAsync.Syntax in
    let load path =
      let%bind data = Fs.readFile path in
      let filename = OpamFile.make (OpamFilename.of_string (Path.toString path)) in
      (* TODO: error handling here *)
      let opam = OpamFile.OPAM.read_from_string ~filename data in
      let opam = OpamFormatUpgrade.opam_file ~filename opam in
      return opam
    in
    match cache with
    | Some cache -> Cache.compute cache path load
    | None -> load path
end

let readFiles (path : Path.t) () =
  let open RunAsync.Syntax in
  let filesPath = Path.(path / "files") in
  if%bind Fs.isDir filesPath
  then
    let collect files filePath _fileStats =
      match Path.relativize ~root:filesPath filePath with
      | Some name ->
        let%bind content = Fs.readFile filePath
        and stats = Fs.stat filePath in
        return ({Package.File. name; content; perm = stats.Unix.st_perm}::files)
      | None -> return files
    in
    Fs.fold ~init:[] ~f:collect filesPath
  else return []

type t = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  path : Path.t;
  opam: OpamFile.OPAM.t;
  url: OpamFile.URL.t option;
  override : Override.t;
  archive : OpamRegistryArchiveIndex.record option;
}

let ofPath ~name ~version (path : Path.t) =
  let open RunAsync.Syntax in
  let%bind opam = File.ofPath path in
  return {
    name; version; path = Path.parent path;
    opam;
    url = None;
    override = Override.empty;
    archive = None;
  }

let ocamlOpamVersionToOcamlNpmVersion v =
  let v = OpamPackage.Version.to_string v in
  SemverVersion.Version.parse v

let toPackage ~name ~version
  {name = opamName; version = opamVersion; opam; url; path; override; archive} =

  let source =
    let open Result.Syntax in

    let sourceOfOpamUrl url =
      let%bind checksum =
        let checksums = OpamFile.URL.checksum url in
        let f c =
          match OpamHash.kind c with
          | `MD5 -> Checksum.Md5, OpamHash.contents c
          | `SHA256 -> Checksum.Sha256, OpamHash.contents c
          | `SHA512 -> Checksum.Sha512, OpamHash.contents c
        in
        match List.map ~f checksums with
        | [] ->
          let msg =
            Format.asprintf
              "no checksum provided for %s@%a"
              name Package.Version.pp version
          in
          Error msg
        | checksum::_ -> Ok checksum
      in

      let convert (url : OpamUrl.t) =
        match url.backend with
        | `http ->
          return (Package.Source (Package.Source.Archive {
            url = OpamUrl.to_string url;
            checksum;
          }))
        | `rsync -> Error "unsupported source for opam: rsync"
        | `hg -> Error "unsupported source for opam: hg"
        | `darcs -> Error "unsupported source for opam: darcs"
        | `git -> Error "unsupported source for opam: git"
      in

      let%bind main = convert (OpamFile.URL.url url) in
      let mirrors =
        let f mirrors url =
          match convert url with
          | Ok mirror -> mirror::mirrors
          | Error _ -> mirrors
        in
        List.fold_left ~f ~init:[] (OpamFile.URL.mirrors url)
      in
      return (main, mirrors)
    in

    let%bind main, mirrors =
      match override.Override.opam.Override.Opam.source with
      | Some source ->
        let main = Package.Source (Package.Source.Archive {
          url = source.url;
          checksum = Checksum.Md5, source.checksum;
        }) in
        return (main, [])
      | None -> begin
        match url with
        | Some url -> sourceOfOpamUrl url
        | None ->
          let main = Package.Source Package.Source.NoSource in
          Ok (main, [])
        end
    in

    match archive with
    | Some archive ->
      let mirrors = main::mirrors in
      let main =
        Package.Source (Package.Source.Archive {
          url = archive.url;
          checksum = Checksum.Md5, archive.md5;
        })
      in
      Ok (main, mirrors)
    | None ->
      Ok (main, mirrors)
  in

  let open RunAsync.Syntax in
  RunAsync.contextf (

    match source with
    | Error err -> return (Error err)
    | Ok source ->

      let translateFormula f =
        let open Result.Syntax in
        let translateAtom ((name, relop) : OpamFormula.atom) =
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
                let%bind v = ocamlOpamVersionToOcamlNpmVersion v in return (C.EQ v)
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
            let module C = OpamVersion.Constraint in
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
        in
        let cnf = OpamFormula.to_cnf f in
        Result.List.map ~f:(Result.List.map ~f:translateAtom) cnf
      in

      let translateFilteredFormula ~build ~post ~test ~doc ~dev f =
        let%bind f =
          try return (OpamFilter.filter_deps ~build ~post ~test ~doc ~dev f)
          with Failure msg -> error msg
        in
        RunAsync.ofStringError (translateFormula f)
      in

      let%bind dependencies =
        let%bind formula =
          RunAsync.context (
            translateFilteredFormula
              ~build:true ~post:true ~test:false ~doc:false ~dev:false
              (OpamFile.OPAM.depends opam)
          ) "processing depends field"
        in
        let formula =
          formula
          @ [
              [{
                Package.Dep.
                name = "@esy-ocaml/substs";
                req = Npm SemverVersion.Constraint.ANY;
              }];
            ]
          @ Package.NpmDependencies.toOpamFormula override.Package.OpamOverride.dependencies
          @ Package.NpmDependencies.toOpamFormula override.Package.OpamOverride.peerDependencies
        in return (Package.Dependencies.OpamFormula formula)
      in

      let%bind devDependencies =
        RunAsync.context (
          let%bind formula =
            translateFilteredFormula
              ~build:false ~post:false ~test:true ~doc:true ~dev:true
              (OpamFile.OPAM.depends opam)
          in return (Package.Dependencies.OpamFormula formula)
        ) "processing depends field"
      in

      let readOpamFilesForPackage path () =
        let%bind files = readFiles path () in
        return (files @ override.Override.opam.files)
      in

      return (Ok {
        Package.
        name;
        version;
        kind = Package.Esy;
        source;
        opam = Some {
          Package.Opam.
          name = opamName;
          version = opamVersion;
          files = readOpamFilesForPackage path;
          opam = opam;
          override = {override with opam = Override.Opam.empty};
        };
        dependencies;
        devDependencies;
      })
  ) "processing %a opam package" Path.pp path
