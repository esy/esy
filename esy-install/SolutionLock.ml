open EsyPackageConfig

type override =
  | OfJson of {json : Json.t}
  | OfPath of Dist.local
  | OfOpamOverride of {path : DistPath.t;}

let override_to_yojson override =
  match override with
  | OfJson {json;} -> json
  | OfPath local -> Dist.local_to_yojson local
  | OfOpamOverride { path; } -> `Assoc [
      "opamoverride", DistPath.to_yojson path;
    ]

let override_of_yojson json =
  let open Result.Syntax in
  match json with
  | `String _ ->
    let%map local = Dist.local_of_yojson json in
    OfPath local
  | `Assoc ["opamoverride", path;] ->
    let%bind path = DistPath.of_yojson path in
    return (OfOpamOverride {path;})
  | `Assoc _ ->
    return (OfJson {json;})
  | _ -> error "expected a string or an object"

type overrides = override list [@@deriving yojson]

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
  source: PackageSource.t;
  overrides: overrides;
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

module PackageOverride = struct
  type t = {
    override : Json.t;
  } [@@deriving of_yojson {strict = false}]

  let ofPath path =
    let open RunAsync.Syntax in
    RunAsync.contextf (
      let%bind json = Fs.readJsonFile path in
      let%bind data = RunAsync.ofRun (Json.parseJsonWith of_yojson json) in
      return data.override
    ) "reading package override %a" Path.pp path
end

let writeOverride sandbox pkg override =
  let open RunAsync.Syntax in
  match override with
  | Override.OfJson {json;} -> return (OfJson {json;})
  | Override.OfOpamOverride info ->
    let id =
      Format.asprintf "%s-%a-opam-override"
        pkg.Package.name
        Version.pp
        pkg.version
    in
    let lockPath = Path.(
      SandboxSpec.solutionLockPath sandbox.Sandbox.spec
      / "overrides"
      / Path.safeSeg id
    ) in
    let%bind () = Fs.copyPath ~src:info.path ~dst:lockPath in
    let path = DistPath.ofPath (Path.tryRelativize ~root:sandbox.spec.path lockPath) in
    return (OfOpamOverride {path;})
  | Override.OfDist {dist = Dist.LocalPath local; json = _;} ->
    return (OfPath local)
  | Override.OfDist {dist; json = _;} ->
    let%bind distPath = DistStorage.fetchIntoCache ~cfg:sandbox.cfg ~sandbox:sandbox.spec dist in
    let digest = Digestv.ofString (Dist.show dist) in
    let lockPath = Path.(
      SandboxSpec.solutionLockPath sandbox.Sandbox.spec
      / "overrides"
      / Digestv.toHex digest
    ) in
    let%bind () = Fs.copyPath ~src:distPath ~dst:lockPath in
    let manifest = Dist.manifest dist in
    let path = DistPath.ofPath (Path.tryRelativize ~root:sandbox.spec.path lockPath) in
    return (OfPath {path; manifest})

let readOverride sandbox override =
  let open RunAsync.Syntax in
  match override with
  | OfJson {json;} -> return (Override.OfJson {json;})
  | OfOpamOverride {path;} ->
    let path = DistPath.toPath sandbox.Sandbox.spec.path path in
    let%bind json = Fs.readJsonFile Path.(path / "package.json") in
    return (Override.OfOpamOverride {json; path;})
  | OfPath local ->
    let filename =
      match local.manifest with
      | None -> "package.json"
      | Some (Esy, filename) -> filename
      | Some (Opam, _filename) -> failwith "cannot load override from opam file"
    in
    let dist = Dist.LocalPath local in
    let path = DistPath.toPath sandbox.Sandbox.spec.path DistPath.(local.path / filename) in
    let%bind json = PackageOverride.ofPath path in
    return (Override.OfDist {dist; json;})

let writeOverrides sandbox pkg overrides =
  RunAsync.List.mapAndJoin ~f:(writeOverride sandbox pkg) overrides

let readOverrides sandbox overrides =
  RunAsync.List.mapAndJoin ~f:(readOverride sandbox) overrides

let writeOpam sandbox (opam : PackageSource.opam) =
  let open RunAsync.Syntax in
  let sandboxPath = sandbox.Sandbox.spec.path in
  let opampath = Path.(sandboxPath // opam.path) in
  let dst =
    let name = OpamPackage.Name.to_string opam.name in
    let version = OpamPackage.Version.to_string opam.version in
    Path.(SandboxSpec.solutionLockPath sandbox.spec / "opam" / (name ^ "." ^ version))
  in
  if Path.isPrefix sandboxPath opampath
  then return opam
  else (
    let%bind () = Fs.copyPath ~src:opam.path ~dst in
    return {opam with path = Path.tryRelativize ~root:sandboxPath dst;}
  )

let readOpam sandbox (opam : PackageSource.opam) =
  let open RunAsync.Syntax in
  let sandboxPath = sandbox.Sandbox.spec.path in
  let opampath = Path.(sandboxPath // opam.path) in
  return {opam with path = opampath;}

let writePackage sandbox (pkg : Package.t) =
  let open RunAsync.Syntax in
  let%bind source =
    match pkg.source with
    | Link { path; manifest } -> return (PackageSource.Link {path; manifest;})
    | Install {source; opam = None;} -> return (PackageSource.Install {source; opam = None;})
    | Install {source; opam = Some opam;} ->
      let%bind opam = writeOpam sandbox opam in
      return (PackageSource.Install {source; opam = Some opam;});
  in
  let%bind overrides = writeOverrides sandbox pkg pkg.overrides in
  return {
    id = pkg.id;
    name = pkg.name;
    version = pkg.version;
    source;
    overrides;
    dependencies = pkg.dependencies;
    devDependencies = pkg.devDependencies;
  }

let readPackage sandbox (node : node) =
  let open RunAsync.Syntax in
  let%bind source =
    match node.source with
    | Link { path; manifest } -> return (PackageSource.Link {path;manifest;})
    | Install {source; opam = None;} -> return (PackageSource.Install {source; opam = None;})
    | Install {source; opam = Some opam;} ->
      let%bind opam = readOpam sandbox opam in
      return (PackageSource.Install {source; opam = Some opam;});
  in
  let%bind overrides = readOverrides sandbox node.overrides in
  return {
    Package.
    id = node.id;
    name = node.name;
    version = node.version;
    source;
    overrides;
    dependencies = node.dependencies;
    devDependencies = node.devDependencies;
  }

let solutionOfLock sandbox root node =
  let open RunAsync.Syntax in
  let f _id node solution =
    let%bind solution = solution in
    let%bind pkg = readPackage sandbox node in
    return (Solution.add pkg solution)
  in
  PackageId.Map.fold f node (return (Solution.empty root))

let lockOfSolution sandbox (solution : Solution.t) =
  let open RunAsync.Syntax in
  let%bind node =
    let f pkg _dependencies nodes =
      let%bind nodes = nodes in
      let%bind node = writePackage sandbox pkg in
      return (
        PackageId.Map.add
          pkg.Package.id
          node
          nodes)
    in
    Solution.fold ~f ~init:(return PackageId.Map.empty) solution
  in
  return (Solution.root solution, node)

let ofPath ~checksum ~(sandbox : Sandbox.t) (path : Path.t) =
  let open RunAsync.Syntax in
  RunAsync.contextf (
    Logs_lwt.debug (fun m -> m "SolutionLock.ofPath %a" Path.pp path);%lwt
    if%bind Fs.exists path
    then
      let%lwt lock =
        let%bind json = Fs.readJsonFile Path.(path / indexFilename) in
        RunAsync.ofRun (Json.parseJsonWith of_yojson json)
      in
      match lock with
      | Ok lock ->
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
  ) "reading lock %a" Path.pp path

let toPath ~checksum ~sandbox ~(solution : Solution.t) (path : Path.t) =
  let open RunAsync.Syntax in
  Logs_lwt.debug (fun m -> m "SolutionLock.toPath %a" Path.pp path);%lwt
  let%bind () = Fs.rmPath path in
  let%bind root, node = lockOfSolution sandbox solution in
  let lock = {checksum; node; root = root.Package.id;} in
  let%bind () = Fs.createDir path in
  let%bind () = Fs.writeJsonFile ~json:(to_yojson lock) Path.(path / indexFilename) in
  let%bind () = Fs.writeFile ~data:gitAttributesContents Path.(path / ".gitattributes") in
  let%bind () = Fs.writeFile ~data:gitIgnoreContents Path.(path / ".gitignore") in
  return ()

let unsafeUpdateChecksum ~checksum path =
  let open RunAsync.Syntax in
  let%bind lock =
    let%bind json = Fs.readJsonFile Path.(path / indexFilename) in
    RunAsync.ofRun (Json.parseJsonWith of_yojson json)
  in
  let lock = {lock with checksum;} in
  Fs.writeJsonFile ~json:(to_yojson lock) Path.(path / indexFilename)
