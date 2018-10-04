module Record = struct

  module Opam = struct
    type t = {
      name : Package.Opam.OpamName.t;
      version : Package.Opam.OpamPackageVersion.t;
      opam : Package.Opam.OpamFile.t;
      override : Package.OpamOverride.t option;
    } [@@deriving yojson]
  end

  module SourceWithMirrors = struct
    type t = Source.t * Source.t list

    let to_yojson = function
      | main, [] -> Source.to_yojson main
      | main, mirrors -> `List (List.map ~f:Source.to_yojson (main::mirrors))

    let of_yojson (json : Json.t) =
      let open Result.Syntax in
      match json with
      | `String _ ->
        let%bind source = Source.of_yojson json in
        return (source, [])
      | `List _ ->
        begin match%bind Json.Decode.list Source.of_yojson json with
        | main::mirrors -> return (main, mirrors)
        | [] -> error "expected a non empty array or a string"
        end
      | _ -> error "expected a non empty array or a string"

  end

  type t = {
    name: string;
    version: Version.t;
    source: SourceWithMirrors.t;
    overrides: Package.Overrides.t [@default Package.Overrides.empty];
    files : Package.File.t list;
    opam : Opam.t option;
  } [@@deriving yojson]

  let id r = PackageId.make r.name r.version

  let compare a b =
    let c = String.compare a.name b.name in
    if c = 0
    then Version.compare a.version b.version
    else c

  let pp fmt record =
    Fmt.pf fmt "%s@%a" record.name Version.pp record.version

  let show = Format.asprintf "%a" pp

  module Map = Map.Make(struct type nonrec t = t let compare = compare end)
  module Set = Set.Make(struct type nonrec t = t let compare = compare end)
end

include Graph.Make(struct
  include Record
  module Id = PackageId
end)

type solution = t

module LockfileV1 = struct

  type t = {
    (* This is hash of all dependencies/resolutios, used as a checksum. *)
    hash : string;
    (* Id of the root package. *)
    root : PackageId.t;
    (* Map from ids to nodes. *)
    node : node PackageId.Map.t
  }

  (* Each package is represented as node. *)
  and node = {
    (* Actual package record. *)
    record : Record.t;
    (* List of dependency ids. *)
    dependencies : PackageId.t StringMap.t;
  } [@@deriving yojson]

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

  let solutionOfLockfile root node =
    let f _id {record; dependencies} solution =
      add record dependencies solution
    in
    PackageId.Map.fold f node (empty root)

  let lockfileOfSolution (sol : solution) =
    let node =
      let f record dependencies nodes =
        let dependencies = StringMap.map Record.id dependencies in
        PackageId.Map.add
          (Record.id record)
          {record; dependencies}
          nodes
      in
      fold ~f ~init:PackageId.Map.empty sol
    in
    root sol, node

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
          let solution = solutionOfLockfile lockfile.root lockfile.node in
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

  let toFile ~sandbox ~(solution : solution) (path : Path.t) =
    let root, node = lockfileOfSolution solution in
    let hash = computeSandboxChecksum sandbox in
    let lockfile = {hash; node; root = Record.id root;} in
    let json = to_yojson lockfile in
    Fs.writeJsonFile ~json path
end
