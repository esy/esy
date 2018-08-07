module Source = Package.Source
module Version = Package.Version
module SourceSpec = Package.SourceSpec
module String = Astring.String
module Override = Package.OpamOverride

module OpamPathsByVersion = Memoize.Make(struct
  type key = OpamPackage.Name.t
  type value = Path.t OpamPackage.Version.Map.t option RunAsync.t
end)

module OpamFileCache = Memoize.Make(struct
  type key = Path.t
  type value = OpamFile.OPAM.t RunAsync.t
end)

type t = {
  init : unit -> registry RunAsync.t;
  lock : Lwt_mutex.t;
  mutable registry : registry option;
}

and registry = {
  repoPath : Path.t;
  overrides : OpamOverrides.t;
  pathsCache : OpamPathsByVersion.t;
  opamCache : OpamFileCache.t;
  archiveIndex : OpamRegistryArchiveIndex.t;
}

type resolution = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  opam: Path.t;
  url: Path.t option;
}

let ocamlOpamVersionToOcamlNpmVersion v =
  let v = OpamPackage.Version.to_string v in
  SemverVersion.Version.parseExn v

let packagePath ~name ~version registry =
  let name = OpamPackage.Name.to_string name in
  let version = OpamPackage.Version.to_string version in
  Path.(
    registry.repoPath
    / "packages"
    / name
    / (name ^ "." ^ version)
  )

let readOpamFileOfPath ?cache path =
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
  | Some cache -> OpamFileCache.compute cache path load
  | None -> load path

let readOpamFileOfRegistry ~name ~version registry =
  let path = Path.(packagePath ~name ~version registry / "opam") in
  readOpamFileOfPath ~cache:registry.opamCache path

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

module Manifest = struct
  type t = {
    name: OpamPackage.Name.t;
    version: OpamPackage.Version.t;
    path : Path.t;
    opam: OpamFile.OPAM.t;
    url: OpamFile.URL.t option;
    override : Override.t;
    archive : OpamRegistryArchiveIndex.record option;
  }

  let ofFile ~name ~version (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind opam = readOpamFileOfPath path in
    return {
      name; version; path = Path.parent path;
      opam;
      url = None;
      override = Override.empty;
      archive = None;
    }

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
                name Version.pp version
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
          let translateAtom ((name, relop) : OpamFormula.atom) =
            let name =
              match OpamPackage.Name.to_string name with
              | "ocaml" -> "ocaml"
              | name -> "@opam/" ^ name
            in
            match name with
            | "ocaml" ->
              let module C = SemverVersion.Constraint in
              let req =
                match relop with
                | None -> C.ANY
                | Some (`Eq, v) -> C.EQ (ocamlOpamVersionToOcamlNpmVersion v)
                | Some (`Neq, v) -> C.NEQ (ocamlOpamVersionToOcamlNpmVersion v)
                | Some (`Lt, v) -> C.LT (ocamlOpamVersionToOcamlNpmVersion v)
                | Some (`Gt, v) -> C.GT (ocamlOpamVersionToOcamlNpmVersion v)
                | Some (`Leq, v) -> C.LTE (ocamlOpamVersionToOcamlNpmVersion v)
                | Some (`Geq, v) -> C.GTE (ocamlOpamVersionToOcamlNpmVersion v)
              in
              {Package.Dep. name; req = Npm req}
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
              {Package.Dep. name; req = Opam req}
          in
          let cnf = OpamFormula.to_cnf f in
          List.map ~f:(List.map ~f:translateAtom) cnf
        in

        let translateFilteredFormula ~build ~post ~test ~doc ~dev f =
          let%bind f =
            try return (OpamFilter.filter_deps ~build ~post ~test ~doc ~dev f)
            with Failure msg -> error msg
          in
          return (translateFormula f)
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
end

let make ~cfg () =
  let init () =
    let open RunAsync.Syntax in
    let%bind repoPath =
      match cfg.Config.opamRepository with
      | Config.Local local -> return local
      | Config.Remote (remote, local) ->
        let update () =
          Logs_lwt.app (fun m -> m "checking %s for updates..." remote);%lwt
          let%bind () = Git.ShallowClone.update ~branch:"2.0.0" ~dst:local remote in
          return local
        in

        if cfg.skipRepositoryUpdate
        then (
          if%bind Fs.exists local
          then return local
          else update ()
        ) else update ()
    in

    let%bind overrides = OpamOverrides.init ~cfg () in
    let%bind archiveIndex = OpamRegistryArchiveIndex.init ~cfg () in

    return {
      repoPath;
      pathsCache = OpamPathsByVersion.make ();
      opamCache = OpamFileCache.make ();
      overrides;
      archiveIndex;
    }
  in {init; lock = Lwt_mutex.create (); registry = None;}

let initRegistry (registry : t) =
  let init () =
    let open RunAsync.Syntax in
    match registry.registry with
    | Some v -> return v
    | None ->
      let%bind v = registry.init () in
      registry.registry <- Some v;
      return v
  in
  Lwt_mutex.with_lock registry.lock init

let getPackageVersionIndex (registry : registry) ~(name : OpamPackage.Name.t) =
  let open RunAsync.Syntax in
  let f name =
    let path = Path.(
      registry.repoPath
      / "packages"
      / OpamPackage.Name.to_string name
    ) in
    if%bind Fs.exists path
    then (
      let%bind entries = Fs.listDir path in
      let f index entry =
        let version = match String.cut ~sep:"." entry with
          | None -> OpamPackage.Version.of_string ""
          | Some (_name, version) -> OpamPackage.Version.of_string version
        in
        OpamPackage.Version.Map.add version Path.(path / entry) index
      in
      return (Some (List.fold_left ~init:OpamPackage.Version.Map.empty ~f entries))
    )
    else
      return None
  in
  OpamPathsByVersion.compute registry.pathsCache name f

let resolve
  ~(name : OpamPackage.Name.t)
  ~(version : OpamPackage.Version.t)
  (registry : registry)
  =
  let open RunAsync.Syntax in
  match%bind getPackageVersionIndex registry ~name with
  | None -> errorf "no opam package %s found" (OpamPackage.Name.to_string name)
  | Some index ->
    begin match OpamPackage.Version.Map.find_opt version index with
    | None -> errorf
        "no opam package %s@%s found"
        (OpamPackage.Name.to_string name) (OpamPackage.Version.to_string version)
    | Some packagePath ->
      let opam = Path.(packagePath / "opam") in
      let%bind url =
        let url = Path.(packagePath / "url") in
        if%bind Fs.exists url
        then return (Some url)
        else return None
      in

      return { name; opam; url; version }
    end

let versions ~(name : OpamPackage.Name.t) registry =
  let open RunAsync.Syntax in
  let%bind registry = initRegistry registry in
  match%bind getPackageVersionIndex registry ~name with
  | None -> errorf "no opam package %s found" (OpamPackage.Name.to_string name)
  | Some index ->
    let queue = LwtTaskQueue.create ~concurrency:2 () in
    let%bind resolutions =
      let getPackageVersion version () =
        resolve ~name ~version registry
      in
      index
      |> OpamPackage.Version.Map.bindings
      |> List.map ~f:(fun (version, _path) -> LwtTaskQueue.submit queue (getPackageVersion version))
      |> RunAsync.List.joinAll
    in
    return resolutions

let version ~(name : OpamPackage.Name.t) ~version registry =
  let open RunAsync.Syntax in
  let%bind registry = initRegistry registry in
  let%bind { opam = _; url; name; version } = resolve registry ~name ~version in
  let%bind pkg =
    let path = packagePath ~name ~version registry in
    let%bind opam = readOpamFileOfRegistry ~name ~version registry in
    let%bind url =
      match OpamFile.OPAM.url opam with
      | Some url -> return (Some url)
      | None ->
        begin match url with
        | Some url ->
          let%bind data = Fs.readFile url in
          return (Some (OpamFile.URL.read_from_string data))
        | None -> return None
        end
    in
    let archive = OpamRegistryArchiveIndex.find ~name ~version registry.archiveIndex in
    return {Manifest.name; version; opam; url; path; override = Override.empty; archive}
  in
  match%bind OpamOverrides.find ~name ~version registry.overrides with
  | None -> return (Some pkg)
  | Some override -> return (Some {pkg with Manifest. override})
