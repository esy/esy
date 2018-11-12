type source =
  | Link of {
      path : DistPath.t;
      manifest : ManifestSpec.t option;
    }
  | Install of {
      source : Source.t * Source.t list;
      opam : OpamResolution.Lock.t option;
    }

let source_of_yojson json =
  let open Result.Syntax in
  let open Json.Decode in
  match%bind fieldWith ~name:"type" string json with
  | "install" ->
    let%bind source =
      match%bind fieldWith ~name:"source" (list Source.of_yojson) json with
      | source::mirrors -> return (source, mirrors)
      | _ -> errorf "invalid source configuration"
    in
    let%bind opam = fieldOptWith ~name:"opam" OpamResolution.Lock.of_yojson json in
    Ok (Install {source; opam;})
  | "link" ->
    let%bind path = fieldWith ~name:"path" DistPath.of_yojson json in
    let%bind manifest = fieldOptWith ~name:"manifest" ManifestSpec.of_yojson json in
    Ok (Link {path; manifest;})
  | typ -> errorf "unknown source type: %s" typ

type t = {
  (* This is checksum of all dependencies/resolutios, used as a checksum. *)
  checksum : string;
  (* Id of the root package. *)
  root : PackageId.t;
  (* Map from ids to nodes. *)
  node : node PackageId.Map.t
} [@@deriving of_yojson]

and node = {
  name: string;
  version: Version.t;
  source: source;
  overrides: Package.Overrides.Lock.t;
  dependencies : PackageId.Set.t;
  devDependencies : PackageId.Set.t;
}

module Encode = struct
  open EsyYarnLockfile.Encode

  let manifestSpec spec =
    string (ManifestSpec.show spec)

  let pkgId source =
    string (PackageId.show source)

  let pkgIdMap encode map =
    let f id value fields = (field (PackageId.show id) encode value)::fields in
    let fields = PackageId.Map.fold f map [] in
    mapping fields

  let pkgIdSet set =
    seq pkgId (PackageId.Set.elements set)

  let pkgSource source =
    string (Source.show source)

  let pkgVersion version =
    string (Version.show version)

  let source source =
    match source with
    | Link {path; manifest;} ->
      mapping [
        field "type" (scalar string) "link";
        field "path" (scalar string) (DistPath.show path);
        fieldOpt "manifest" (scalar manifestSpec) manifest;
      ]
    | Install {source = source, mirrors; opam = _;} ->
      mapping [
        field "type" (scalar string) "install";
        field "source" (seq pkgSource) (source::mirrors);
        (* TODO: *)
        (* fieldOpt "manifest" manifestSpec_to_lock manifest; *)
      ]

  let node node =
    mapping [
      field "name" (scalar string) node.name;
      field "version" (scalar pkgVersion) node.version;
      field "source" source node.source;
      field "dependencies" pkgIdSet node.dependencies;
      field "devDependencies" pkgIdSet node.devDependencies;
      (* TODO: overrides *)
    ]

  let lock lock =
    mapping [
      field "checksum" (scalar string) lock.checksum;
      field "root" (scalar pkgId) lock.root;
      field "node" (pkgIdMap node) lock.node;
    ]
end

(* module Decode = struct *)
(*   open EsyYarnLockfile.Decode *)
(*   open Result.Syntax *)

(*   let manifestSpec spec = *)
(*     string (ManifestSpec.show spec) *)

(*   let pkgId tree = *)
(*     let%bind s = string tree in *)
(*     PackageId.parse s *)

(*   let pkgIdMap decode map = *)
(*     let f id value fields = (field (PackageId.show id) encode value)::fields in *)
(*     let fields = PackageId.Map.fold f map [] in *)
(*     mapping fields *)

(*   let pkgSource tree = *)
(*     let%bind s = string tree in *)
(*     Source.parse s *)

(*   let pkgVersion tree = *)
(*     let%bind s = string tree in *)
(*     Version.parse s *)

(*   let source source = *)
(*     match source with *)
(*     | Link {path; manifest;} -> *)
(*       mapping [ *)
(*         field "type" (scalar string) "link"; *)
(*         field "path" (scalar string) (DistPath.show path); *)
(*         fieldOpt "manifest" (scalar manifestSpec) manifest; *)
(*       ] *)
(*     | Install {source = source, mirrors; opam = _;} -> *)
(*       mapping [ *)
(*         field "type" (scalar string) "install"; *)
(*         field "source" (seq pkgSource) (source::mirrors); *)
(*         (1* TODO: *1) *)
(*         (1* fieldOpt "manifest" manifestSpec_to_lock manifest; *1) *)
(*       ] *)

(*   let node tree = *)
(*     let%bind fields = mapping tree in *)
(*     let%bind name = field "name" (scalar string) fields in *)
(*     let%bind version = field "version" (scalar pkgVersion) fields in *)
(*     let%bind source = field "source" (scalar pkgSource) fields in *)
(*     (1* TODO: overrides, dependencies, devDependencies *1) *)
(*     return {name; version; source;} *)

(*   let lock tree = *)
(*     let%bind fields = mapping tree in *)
(*     let%bind checksum = field "checksum" (scalar string) fields in *)
(*     let%bind root = field "root" (scalar pkgId) fields in *)
(*     let%bind node = field "node" (pkgIdMap node) fields in *)
(*     return {checksum; node; root;} *)
(* end *)

let indexFilename = "index.json"

let ofPackage sandbox (pkg : Solution.Package.t) =
  let open RunAsync.Syntax in
  let%bind source =
    match pkg.source with
    | Package.Link { path; manifest } -> return (Link {path; manifest;})
    | Install {source; opam = None;} -> return (Install {source; opam = None;})
    | Install {source; opam = Some opam;} ->
      let%bind opam = OpamResolution.toLock ~sandbox:sandbox.spec opam in
      return (Install {source; opam = Some opam;});
  in
  let%bind overrides =
    Package.Overrides.toLock
      ~sandbox:sandbox.Sandbox.spec
      pkg.overrides
  in
  return {
    name = pkg.name;
    version = pkg.version;
    source;
    overrides;
    dependencies = pkg.dependencies;
    devDependencies = pkg.devDependencies;
  }

let toPackage sandbox (node : node) =
  let open RunAsync.Syntax in
  let%bind source =
    match node.source with
    | Link { path; manifest } -> return (Package.Link {path;manifest;})
    | Install {source; opam = None;} -> return (Package.Install {source; opam = None;})
    | Install {source; opam = Some opam;} ->
      let%bind opam = OpamResolution.ofLock ~sandbox:sandbox.Sandbox.spec opam in
      return (Package.Install {source; opam = Some opam;});
  in
  return {
    Solution.Package.
    name = node.name;
    version = node.version;
    source;
    overrides = Package.Overrides.ofLock ~sandbox:sandbox.Sandbox.spec node.overrides;
    dependencies = node.dependencies;
    devDependencies = node.devDependencies;
  }

let computeSandboxChecksum (sandbox : Sandbox.t) =
  let open RunAsync.Syntax in

  let ppDependencies fmt deps =

    let ppOpamDependencies fmt deps =
      let ppDisj fmt disj =
        match disj with
        | [] -> Fmt.unit "true" fmt ()
        | [dep] -> Package.Dep.pp fmt dep
        | deps -> Fmt.pf fmt "(%a)" Fmt.(list ~sep:(unit " || ") Package.Dep.pp) deps
      in
      Fmt.pf fmt "@[<h>[@;%a@;]@]" Fmt.(list ~sep:(unit " && ") ppDisj) deps
    in

    let ppNpmDependencies fmt deps =
      let ppDnf ppConstr fmt f =
        let ppConj = Fmt.(list ~sep:(unit " && ") ppConstr) in
        Fmt.(list ~sep:(unit " || ") ppConj) fmt f
      in
      let ppVersionSpec fmt spec =
        match spec with
        | VersionSpec.Npm f ->
          ppDnf SemverVersion.Constraint.pp fmt f
        | VersionSpec.NpmDistTag tag ->
          Fmt.string fmt tag
        | VersionSpec.Opam f ->
          ppDnf OpamPackageVersion.Constraint.pp fmt f
        | VersionSpec.Source src ->
          Fmt.pf fmt "%a" SourceSpec.pp src
      in
      let ppReq fmt req =
        Fmt.fmt "%s@%a" fmt req.Req.name ppVersionSpec req.spec
      in
      Fmt.pf fmt "@[<hov>[@;%a@;]@]" (Fmt.list ~sep:(Fmt.unit ", ") ppReq) deps
    in

    match deps with
    | Package.Dependencies.OpamFormula deps -> ppOpamDependencies fmt deps
    | Package.Dependencies.NpmFormula deps -> ppNpmDependencies fmt deps
  in

  let showDependencies (deps : Package.Dependencies.t) =
    Format.asprintf "%a" ppDependencies deps
  in

  let hashDependencies ~dependencies digest =
    Digest.string (digest ^ "__" ^ showDependencies dependencies)
  in
  let hashResolutions ~resolutions digest =
    Digest.string (digest ^ "__" ^ Package.Resolutions.digest resolutions)
  in

  let digest =
    Digest.string ""
    |> hashResolutions
      ~resolutions:sandbox.resolutions
    |> hashDependencies
      ~dependencies:sandbox.root.dependencies
    |> hashDependencies
      ~dependencies:sandbox.root.devDependencies
  in

  let%bind digest =
    let f digest resolution =
      let resolution =
        match resolution.Package.Resolution.resolution with
        | SourceOverride {source = Source.Link _; override = _;} -> Some resolution
        | SourceOverride _ -> None
        | Version (Version.Source (Source.Link _)) -> Some resolution
        | Version _ -> None
      in
      match resolution with
      | None -> return digest
      | Some resolution ->
        begin match%bind Resolver.package ~resolution sandbox.resolver with
        | Error _ ->
          errorf "unable to read package: %a" Package.Resolution.pp resolution
        | Ok pkg ->
          return (
            digest
            |> hashDependencies
              ~dependencies:pkg.Package.dependencies
          )
        end
    in
    RunAsync.List.foldLeft
      ~f
      ~init:digest
      (Package.Resolutions.entries sandbox.resolutions)
  in

  return (Digest.to_hex digest)

let solutionOfLock sandbox root node =
  let open RunAsync.Syntax in
  let f _id node solution =
    let%bind solution = solution in
    let%bind pkg = toPackage sandbox node in
    return (Solution.add pkg solution)
  in
  PackageId.Map.fold f node (return (Solution.empty root))

let lockOfSolution sandbox (solution : Solution.t) =
  let open RunAsync.Syntax in
  let%bind node =
    let f pkg _dependencies nodes =
      let%bind nodes = nodes in
      let%bind node = ofPackage sandbox pkg in
      return (PackageId.Map.add
        (Solution.Package.id pkg)
        node
        nodes)
    in
    Solution.fold ~f ~init:(return PackageId.Map.empty) solution
  in
  return (Solution.root solution, node)

let ofPath ~(sandbox : Sandbox.t) (path : Path.t) =
  let open RunAsync.Syntax in
  Logs_lwt.debug (fun m -> m "SolutionLock.ofPath %a" Path.pp path);%lwt
  if%bind Fs.exists path
  then
    let%lwt lock =
      let%bind json = Fs.readJsonFile Path.(path / indexFilename) in
      RunAsync.ofRun (Json.parseJsonWith of_yojson json)
    in
    match lock with
    | Ok lock ->
      let%bind checksum = computeSandboxChecksum sandbox in
      if String.compare lock.checksum checksum = 0
      then
        let%bind solution = solutionOfLock sandbox lock.root lock.node in
        return (Some solution)
      else return None
    | Error err ->
      let path =
        Option.orDefault
          ~default:path
          (Path.relativize ~root:sandbox.spec.path path)
      in
      errorf
        "corrupted %a lock@\nyou might want to remove it and install from scratch@\nerror: %a"
        Path.pp path Run.ppError err
  else
    return None

let toPath ~sandbox ~(solution : Solution.t) (path : Path.t) =
  let open RunAsync.Syntax in
  Logs_lwt.debug (fun m -> m "SolutionLock.toPath %a" Path.pp path);%lwt
  let%bind () = Fs.rmPath path in
  let%bind root, node = lockOfSolution sandbox solution in
  let%bind checksum = computeSandboxChecksum sandbox in
  let lock = {checksum; node; root = Solution.Package.id root;} in
  let%bind () = Fs.createDir path in
  let data =
    let s = Encode.lock lock in
    Format.asprintf "%a" EsyYarnLockfile.pp s
  in
  Fs.writeFile ~data Path.(path / indexFilename)
