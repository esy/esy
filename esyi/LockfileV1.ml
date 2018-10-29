type source = Package.source

let source_to_yojson source =
  let open Json.Encode in
  match source with
  | Package.Link { path; manifest } ->
    assoc [
      field "type" string "link";
      field "path" Path.to_yojson path;
      fieldOpt "manifest" ManifestSpec.to_yojson manifest;
    ]
  | Package.Install { source = source, mirrors; opam } ->
    assoc [
      field "type" string "install";
      field "source" (Json.Encode.list Source.to_yojson) (source::mirrors);
      fieldOpt "opam" OpamResolution.to_yojson opam;
    ]

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
    let%bind opam = fieldOptWith ~name:"opam" OpamResolution.of_yojson json in
    Ok (Package.Install {source; opam;})
  | "link" ->
    let%bind path = fieldWith ~name:"path" Path.of_yojson json in
    let%bind manifest = fieldOptWith ~name:"manifest" ManifestSpec.of_yojson json in
    Ok (Package.Link {path; manifest;})
  | typ -> errorf "unknown source type: %s" typ

type t = {
  (* This is checksum of all dependencies/resolutios, used as a checksum. *)
  checksum : string;
  (* Id of the root package. *)
  root : PackageId.t;
  (* Map from ids to nodes. *)
  node : node PackageId.Map.t
} [@@deriving yojson]

and node = {
  name: string;
  version: Version.t;
  source: source;
  overrides: Package.Overrides.t;
  dependencies : PackageId.Set.t;
  devDependencies : PackageId.Set.t;
}

let indexFilename = "index.json"

let opampathLocked sandbox (opam : OpamResolution.t) =
  let name = OpamPackage.Name.to_string opam.name in
  let version = OpamPackage.Version.to_string opam.version in
  Path.(SandboxSpec.lockfilePath sandbox.Sandbox.spec / "opam" / (name ^ "." ^ version))

let ofPackage sandbox (pkg : Solution.Package.t) =
  let open RunAsync.Syntax in
  let%bind source =
    match pkg.source with
    | Link _
    | Install {source = _; opam = None;} -> return pkg.source
    | Install {source; opam = Some opam;} ->
      let sandboxPath = sandbox.Sandbox.spec.path in
      let opampath = Path.(sandboxPath // opam.path) in
      let opampathLocked = opampathLocked sandbox opam in
      if Path.isPrefix sandboxPath opampath
      then return pkg.source
      else (
        Logs_lwt.debug (
          fun m ->
            m "lock: %a -> %a"
            Path.pp opam.path
            Path.pp opampathLocked
        );%lwt
        let%bind () = Fs.copyPath ~src:opam.path ~dst:opampathLocked in
        return (Package.Install {
          source;
          opam = Some {
            opam with path = Path.tryRelativize ~root:sandboxPath opampathLocked;
          }
        });
      )
  in
  return {
    name = pkg.name;
    version = pkg.version;
    source;
    overrides = pkg.overrides;
    dependencies = pkg.dependencies;
    devDependencies = pkg.devDependencies;
  }

let toPackage _sandbox (node : node) =
  let open RunAsync.Syntax in
  return {
    Solution.Package.
    name = node.name;
    version = node.version;
    source = node.source;
    overrides = node.overrides;
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
      ~dependencies:sandbox.dependencies
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
            Digest.string ""
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

let solutionOfLockfile sandbox root node =
  let open RunAsync.Syntax in
  let f _id node solution =
    let%bind solution = solution in
    let%bind pkg = toPackage sandbox node in
    return (Solution.add pkg solution)
  in
  PackageId.Map.fold f node (return (Solution.empty root))

let lockfileOfSolution sandbox (solution : Solution.t) =
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
  Logs_lwt.debug (fun m -> m "LockfileV1.ofPath %a" Path.pp path);%lwt
  if%bind Fs.exists path
  then
    let%lwt lockfile =
      let%bind json = Fs.readJsonFile Path.(path / indexFilename) in
      RunAsync.ofRun (Json.parseJsonWith of_yojson json)
    in
    match lockfile with
    | Ok lockfile ->
      let%bind checksum = computeSandboxChecksum sandbox in
      if String.compare lockfile.checksum checksum = 0
      then
        let%bind solution = solutionOfLockfile sandbox lockfile.root lockfile.node in
        return (Some solution)
      else return None
    | Error err ->
      let path =
        Option.orDefault
          ~default:path
          (Path.relativize ~root:sandbox.spec.path path)
      in
      errorf
        "corrupted %a lockfile@\nyou might want to remove it and install from scratch@\nerror: %a"
        Path.pp path Run.ppError err
  else
    return None

let toPath ~sandbox ~(solution : Solution.t) (path : Path.t) =
  let open RunAsync.Syntax in
  Logs_lwt.debug (fun m -> m "LockfileV1.toPath %a" Path.pp path);%lwt
  let%bind () = Fs.rmPath path in
  let%bind root, node = lockfileOfSolution sandbox solution in
  let%bind checksum = computeSandboxChecksum sandbox in
  let lockfile = {checksum; node; root = Solution.Package.id root;} in
  let%bind () = Fs.createDir path in
  Fs.writeJsonFile ~json:(to_yojson lockfile) Path.(path / indexFilename)
