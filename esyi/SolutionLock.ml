type source =
  | Link of Source.link
  | Install of {
      source : Dist.t * Dist.t list;
      opam : OpamResolution.Lock.t option;
    }

let source_to_yojson source =
  let open Json.Encode in
  match source with
  | Link { path; manifest } ->
    assoc [
      field "type" string "link";
      field "path" DistPath.to_yojson path;
      fieldOpt "manifest" ManifestSpec.to_yojson manifest;
    ]
  | Install { source = source, mirrors; opam } ->
    assoc [
      field "type" string "install";
      field "source" (Json.Encode.list Dist.to_yojson) (source::mirrors);
      fieldOpt "opam" OpamResolution.Lock.to_yojson opam;
    ]

let source_of_yojson json =
  let open Result.Syntax in
  let open Json.Decode in
  match%bind fieldWith ~name:"type" string json with
  | "install" ->
    let%bind source =
      match%bind fieldWith ~name:"source" (list Dist.of_yojson) json with
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
} [@@deriving yojson]

and node = {
  id: PackageId.t;
  name: string;
  version: Version.t;
  source: source;
  overrides: Package.Overrides.Lock.t;
  dependencies : PackageId.Set.t;
  devDependencies : PackageId.Set.t;
}

let indexFilename = "index.json"

let gitAttributesContents = {|
# Set eol to LF so files aren't converted to CRLF-eol on Windows.
* text eol=lf
|}

let gitIgnoreContents = {|
# Reset any possible .gitignore, we want all esy.lock to be un-ignored.
!*
|}

let ofPackage sandbox (pkg : Solution.Package.t) =
  let open RunAsync.Syntax in
  let%bind source =
    match pkg.source with
    | Link { path; manifest } -> return (Link {path; manifest;})
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
    id = pkg.id;
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
    id = node.id;
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
      return (
        PackageId.Map.add
          pkg.Solution.Package.id
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
  let lock = {checksum; node; root = root.Solution.Package.id;} in
  let%bind () = Fs.createDir path in
  let%bind () = Fs.writeJsonFile ~json:(to_yojson lock) Path.(path / indexFilename) in
  let%bind () = Fs.writeFile ~data:gitAttributesContents Path.(path / ".gitattributes") in
  let%bind () = Fs.writeFile ~data:gitIgnoreContents Path.(path / ".gitignore") in
  return ()

let unsafeUpdateChecksum ~sandbox path =
  let open RunAsync.Syntax in
  let%bind lock =
    let%bind json = Fs.readJsonFile Path.(path / indexFilename) in
    RunAsync.ofRun (Json.parseJsonWith of_yojson json)
  in
  let%bind checksum = computeSandboxChecksum sandbox in
  let lock = {lock with checksum;} in
  Fs.writeJsonFile ~json:(to_yojson lock) Path.(path / indexFilename)
