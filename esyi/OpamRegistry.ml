module Source = Package.Source
module Version = Package.Version
module SourceSpec = Package.SourceSpec
module String = Astring.String
module Override = Package.OpamOverride

module OpamPathsByVersion = Memoize.Make(struct
  type key = OpamPackage.Name.t
  type value = Path.t OpamPackage.Version.Map.t RunAsync.t
end)

module OpamFiles = Memoize.Make(struct
  type key = OpamPackage.Name.t * OpamPackage.Version.t
  type value = OpamFile.OPAM.t RunAsync.t
end)

module OpamArchivesIndex : sig
  type t

  type record = {
    url: string;
    md5: string
  }

  val init : cfg:Config.t -> unit -> t RunAsync.t
  val find : name:OpamPackage.Name.t -> version:OpamPackage.Version.t -> t -> record option

end = struct
  type t = {
    index : record StringMap.t;
    cacheKey : (string option [@default None]);
  } [@@deriving yojson]

  and record = {
    url: string;
    md5: string
  }

  let baseUrl = "https://opam.ocaml.org/"
  let url = baseUrl ^ "/urls.txt"

  let parse response =

    let parseBase =
      Re.(compile (seq [bos; str "archives/"; group (rep1 any); str "+opam.tar.gz"; eos]))
    in

    let attrs = OpamFile.File_attributes.read_from_string response in
    let f attr index =
      let base = OpamFilename.(Base.to_string (Attribute.base attr)) in
      let md5 =
        let hash = OpamFilename.Attribute.md5 attr in
        OpamHash.contents hash
      in
      match Re.exec_opt parseBase base with
      | Some m ->
        let id = Re.Group.get m 1 in
        let url = baseUrl ^ base in
        let record = {url; md5} in
        StringMap.add id record index
      | None -> index
    in
    OpamFilename.Attribute.Set.fold f attrs StringMap.empty

  let download () =
    let open RunAsync.Syntax in
    Logs_lwt.app (fun m -> m "downloading opam index...");%lwt
    let%bind data = Curl.get url in
    return (parse data)

  let init ~cfg () =
    let open RunAsync.Syntax in
    let filename = cfg.Config.opamArchivesIndexPath in

    let cacheKeyOfHeaders headers =
      let contentLength = StringMap.find_opt "content-length" headers in
      let lastModified = StringMap.find_opt "last-modified" headers in
      match contentLength, lastModified with
      | Some a, Some b -> Some Digest.(a ^ "__" ^ b |> string |> to_hex)
      | _ -> None
    in

    let save index =
      let json = to_yojson index in
      Fs.writeJsonFile ~json filename
    in

    let downloadAndSave () =
      let%bind headers = Curl.head url in
      let cacheKey = cacheKeyOfHeaders headers in
      let%bind index =
        let%bind index = download () in
        return {cacheKey; index}
      in
      let%bind () = save index in
      return index
    in

    if%bind Fs.exists filename
    then
      let%bind json = Fs.readJsonFile filename in
      let%bind index = RunAsync.ofRun (Json.parseJsonWith of_yojson json) in
      let%bind headers = Curl.head url in
      begin match index.cacheKey, cacheKeyOfHeaders headers with
      | Some cacheKey, Some currCacheKey ->
        if cacheKey = currCacheKey
        then return index
        else
          let%bind index =
            let%bind index = download () in
            return {index; cacheKey = Some currCacheKey}
          in
          let%bind () = save index in
          return index
      | _ -> downloadAndSave ()
      end
    else downloadAndSave ()

  let find ~name ~version index =
    let key =
      let name = OpamPackage.Name.to_string name in
      let version = OpamPackage.Version.to_string version in
      name ^ "." ^ version
    in
    StringMap.find_opt key index.index
end

type t = {
  init : unit -> registry RunAsync.t;
  lock : Lwt_mutex.t;
  mutable registry : registry option;
}

and registry = {
  repoPath : Path.t;
  overrides : OpamOverrides.t;
  pathsCache : OpamPathsByVersion.t;
  opamCache : OpamFiles.t;
  archiveIndex : OpamArchivesIndex.t;
}

type resolution = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  opam: Path.t;
  url: Path.t option;
}

let packagePath ~name ~version registry =
  let name = OpamPackage.Name.to_string name in
  let version = OpamPackage.Version.to_string version in
  Path.(
    registry.repoPath
    / "packages"
    / name
    / (name ^ "." ^ version)
  )

let readOpamFile ~name ~version registry =
  let open RunAsync.Syntax in
  let compute (name, version) =
    let path = Path.(packagePath ~name ~version registry / "opam") in
    let%bind data = Fs.readFile path in
    return (OpamFile.OPAM.read_from_string data)
  in
  OpamFiles.compute registry.opamCache (name, version) compute

let readOpamFiles (path : Path.t) () =
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
    archive : OpamArchivesIndex.record option;
  }

  let ofFile ~name ~version (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind data = Fs.readFile path in
    let opam = OpamFile.OPAM.read_from_string data in 
    return {
      name; version; path = Path.parent path;
      opam;
      url = None;
      override = Override.empty;
      archive = None;
    }

  let ofRegistry ~name ~version ?url registry =
    let open RunAsync.Syntax in
    let path = packagePath ~name ~version registry in
    let%bind opam = readOpamFile ~name ~version registry in
    let%bind url =
      match url with
      | Some url ->
        let%bind data = Fs.readFile url in
        return (Some (OpamFile.URL.read_from_string data))
      | None -> return None
    in
    let archive = OpamArchivesIndex.find ~name ~version registry.archiveIndex in
    return {name; version; opam; url; path; override = Override.empty; archive}

  let toPackage ~name ~version
    {name = opamName; version = opamVersion; opam; url; path; override; archive} =
    let open RunAsync.Syntax in
    let context = Format.asprintf "processing %a opam package" Path.pp path in
    RunAsync.withContext context (

      let%bind source = RunAsync.ofRun (
        let open Run.Syntax in

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
              error (Format.asprintf "no checksum provided for %s@%a" name Version.pp version)
            | checksum::_ -> return checksum
          in

          let convert (url : OpamUrl.t) =
            match url.backend with
            | `http ->
              return (Package.Source (Package.Source.Archive {
                url = OpamUrl.to_string url;
                checksum;
              }))
            | `rsync -> error "unsupported source for opam: rsync"
            | `hg -> error "unsupported source for opam: hg"
            | `darcs -> error "unsupported source for opam: darcs"
            | `git -> error "unsupported source for opam: git"
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
              return (main, [])
            end
        in

        let main, mirrors =
          match archive with
          | Some archive ->
            let mirrors = main::mirrors in
            let main =
              Package.Source (Package.Source.Archive {
                url = archive.url;
                checksum = Checksum.Md5, archive.md5;
              })
            in
            main, mirrors
          | None ->
            main, mirrors
        in

        return (main, mirrors)
      ) in

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

      let translateFilteredFormula ~build ~post ~test ~doc ~dev f =
        let%bind f =
          let env var =
            match OpamVariable.Full.to_string var with
            | "test" -> Some (OpamVariable.B test)
            | "doc" -> Some (OpamVariable.B doc)
            | _ -> None
          in
          let f = OpamFilter.partial_filter_formula env f in
          try return (OpamFilter.filter_deps ~build ~post ~test ~doc ~dev f)
          with Failure msg -> error msg
        in
        return (translateFormula f)
      in

      let%bind dependencies =
        let%bind formula =
          RunAsync.withContext "processing depends field" (
            translateFilteredFormula
              ~build:true ~post:true ~test:false ~doc:false ~dev:false
              (OpamFile.OPAM.depends opam)
          )
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
        RunAsync.withContext "processing depends field" (
          let%bind formula =
            translateFilteredFormula
              ~build:false ~post:false ~test:true ~doc:true ~dev:true
              (OpamFile.OPAM.depends opam)
          in return (Package.Dependencies.OpamFormula formula)
        )
      in

      let readOpamFilesForPackage path () =
        let%bind files = readOpamFiles path () in
        return (files @ override.Override.opam.files)
      in

      return {
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
      }
    )
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
          let%bind () = Git.ShallowClone.update ~branch:"master" ~dst:local remote in
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
    let%bind archiveIndex = OpamArchivesIndex.init ~cfg () in

    return {
      repoPath;
      pathsCache = OpamPathsByVersion.make ();
      opamCache = OpamFiles.make ();
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

let getVersionIndex (registry : registry) ~(name : OpamPackage.Name.t) =
  let open RunAsync.Syntax in
  let f name =
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

let getPackage
  ?ocamlVersion
  ~(name : OpamPackage.Name.t)
  ~(version : OpamPackage.Version.t)
  (registry : registry)
  =
  let open RunAsync.Syntax in
  let%bind index = getVersionIndex registry ~name in
  match OpamPackage.Version.Map.find_opt version index with
  | None -> return None
  | Some packagePath ->
    let opam = Path.(packagePath / "opam") in
    let%bind url =
      let url = Path.(packagePath / "url") in
      if%bind Fs.exists url
      then return (Some url)
      else return None
    in

    let%bind available =
      let env (var : OpamVariable.Full.t) =
        let scope = OpamVariable.Full.scope var in
        let name = OpamVariable.Full.variable var in
        let v =
          let open Option.Syntax in
          let open OpamVariable in
          match scope, OpamVariable.to_string name with
          | OpamVariable.Full.Global, "preinstalled" ->
            return (bool false)
          | OpamVariable.Full.Global, "compiler"
          | OpamVariable.Full.Global, "ocaml-version" ->
            let%bind ocamlVersion = ocamlVersion in
            return (string (OpamPackage.Version.to_string ocamlVersion))
          | OpamVariable.Full.Global, _ -> None
          | OpamVariable.Full.Self, _ -> None
          | OpamVariable.Full.Package _, _ -> None
        in v
      in
      let%bind opam = readOpamFile ~name ~version registry in
      let formula = OpamFile.OPAM.available opam in
      let available = OpamFilter.eval_to_bool ~default:true env formula in
      return available
    in

    if available
    then return (Some { name; opam; url; version })
    else return None

let versions ?ocamlVersion ~(name : OpamPackage.Name.t) registry =
  let open RunAsync.Syntax in
  let%bind registry = initRegistry registry in
  let%bind index = getVersionIndex registry ~name in
  let queue = LwtTaskQueue.create ~concurrency:2 () in
  let%bind resolutions =
    let getPackageVersion version () =
      getPackage ?ocamlVersion ~name ~version registry
    in
    index
    |> OpamPackage.Version.Map.bindings
    |> List.map ~f:(fun (version, _path) -> LwtTaskQueue.submit queue (getPackageVersion version))
    |> RunAsync.List.joinAll
  in
  return (List.filterNone resolutions)

let version ~(name : OpamPackage.Name.t) ~version registry =
  let open RunAsync.Syntax in
  let%bind registry = initRegistry registry in
  match%bind getPackage registry ~name ~version with
  | None -> return None
  | Some { opam = _; url; name; version } ->
    let%bind pkg = Manifest.ofRegistry ~name ~version ?url registry in
    begin match%bind OpamOverrides.find ~name ~version registry.overrides with
    | None -> return (Some pkg)
    | Some override -> return (Some {pkg with Manifest. override})
    end
