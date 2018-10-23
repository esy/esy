type t = {
  (* This is hash of all dependencies/resolutios, used as a checksum. *)
  hash : string;
  (* Id of the root package. *)
  root : PackageId.t;
  (* Map from ids to nodes. *)
  node : node PackageId.Map.t
} [@@deriving yojson]

and node = {
  name: string;
  version: Version.t;
  source: Solution.Package.source;
  overrides: override list;
  dependencies : PackageId.Set.t;
  devDependencies : PackageId.Set.t;
}

and override =
  | InlineOverride of Package.Resolution.override
  | Override of Source.t

let readOverride sandbox override =
  let open RunAsync.Syntax in
  match override with
  | InlineOverride override -> return override
  | Override source ->
    let%bind path =
      match source with
      | Source.Dist dist -> FetchStorage.fetchDist ~sandbox dist
      | Source.Link {path; manifest = _;} -> return path
    in
    let manifest =
      match Source.manifest source with
      | None -> ManifestSpec.One (ManifestSpec.Filename.Esy, "package.json")
      | Some manifest -> manifest
    in
    begin match manifest with
    | ManifestSpec.One (ManifestSpec.Filename.Esy, filename) ->
      let path = Path.(path / filename) in
      let%bind json = Fs.readJsonFile path in
      let%bind override = RunAsync.ofStringError (DistResolver.PackageOverride.of_yojson json) in
      return override.DistResolver.PackageOverride.override
    | manifest ->
      errorf "unable to read override from %a" ManifestSpec.pp manifest
    end

let toPackage sandbox (node : node) =
  let open RunAsync.Syntax in
  let%bind overrides =
    let%bind overrides =
      RunAsync.List.mapAndJoin
        ~f:(readOverride sandbox)
        node.overrides
    in
    return Package.Overrides.(addMany overrides empty)
  in
  return {
    Solution.Package.
    name = node.name;
    version = node.version;
    source = node.source;
    overrides;
    dependencies = node.dependencies;
    devDependencies = node.devDependencies;
  }

let ofPackage (pkg : Solution.Package.t) =
  let ofOverride override =
    match override.Package.Resolution.origin with
    | Some source -> Override source
    | None -> InlineOverride override
  in
  {
    name = pkg.name;
    version = pkg.version;
    source = pkg.source;
    overrides = List.map ~f:ofOverride (Package.Overrides.toList pkg.overrides);
    dependencies = pkg.dependencies;
    devDependencies = pkg.devDependencies;
  }

let computeSandboxChecksum (sandbox : Sandbox.t) =

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
  Digest.to_hex digest

let solutionOfLockfile sandbox root node =
  let open RunAsync.Syntax in
  let f _id node solution =
    let%bind solution = solution in
    let%bind pkg = toPackage sandbox node in
    return (Solution.add pkg solution)
  in
  PackageId.Map.fold f node (return (Solution.empty root))

let lockfileOfSolution (sol : Solution.t) =
  let node =
    let f pkg _dependencies nodes =
      PackageId.Map.add
        (Solution.Package.id pkg)
        (ofPackage pkg)
        nodes
    in
    Solution.fold ~f ~init:PackageId.Map.empty sol
  in
  Solution.root sol, node

let ofFile ~(sandbox : Sandbox.t) (path : Path.t) =
  let open RunAsync.Syntax in
  if%bind Fs.exists path
  then
    let%lwt lockfile =
      let%bind json = Fs.readJsonFile path in
      RunAsync.ofRun (Json.parseJsonWith of_yojson json)
    in
    match lockfile with
    | Ok lockfile ->
      if lockfile.hash = computeSandboxChecksum sandbox
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

let toFile ~sandbox ~(solution : Solution.t) (path : Path.t) =
  let root, node = lockfileOfSolution solution in
  let hash = computeSandboxChecksum sandbox in
  let lockfile = {hash; node; root = Solution.Package.id root;} in
  let json = to_yojson lockfile in
  Fs.writeJsonFile ~json path
