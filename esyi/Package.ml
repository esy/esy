module String = Astring.String

[@@@ocaml.warning "-32"]
type 'a disj = 'a list [@@deriving eq]
[@@@ocaml.warning "-32"]
type 'a conj = 'a list [@@deriving eq]

module Dep = struct
  type t = {
    name : string;
    req : req;
  }

  and req =
    | Npm of SemverVersion.Constraint.t
    | NpmDistTag of string
    | Opam of OpamPackageVersion.Constraint.t
    | Source of SourceSpec.t

  let matches ~name ~version dep =
    name = dep.name &&
      match version, dep.req with
      | Version.Npm version, Npm c -> SemverVersion.Constraint.matches ~version c
      | Version.Npm _, _ -> false
      | Version.Opam version, Opam c -> OpamPackageVersion.Constraint.matches ~version c
      | Version.Opam _, _ -> false
      | Version.Source source, Source c -> SourceSpec.matches ~source c
      | Version.Source _, _ -> false

  let pp fmt {name; req;} =
    let ppReq fmt = function
      | Npm c -> SemverVersion.Constraint.pp fmt c
      | NpmDistTag tag -> Fmt.string fmt tag
      | Opam c -> OpamPackageVersion.Constraint.pp fmt c
      | Source src -> SourceSpec.pp fmt src
    in
    Fmt.pf fmt "%s@%a" name ppReq req

end

module Dependencies = struct

  type t =
    | OpamFormula of Dep.t disj conj
    | NpmFormula of Req.t conj

  let toApproximateRequests = function
    | NpmFormula reqs -> reqs
    | OpamFormula reqs ->
      let reqs =
        let f reqs deps =
          let f reqs (dep : Dep.t) =
            let spec =
              match dep.req with
              | Dep.Npm _ -> VersionSpec.Npm [[SemverVersion.Constraint.ANY]]
              | Dep.NpmDistTag tag -> VersionSpec.NpmDistTag (tag, None)
              | Dep.Opam _ -> VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]]
              | Dep.Source srcSpec -> VersionSpec.Source srcSpec
            in
            Req.Set.add (Req.make ~name:dep.name ~spec) reqs
          in
          List.fold_left ~f ~init:reqs deps
        in
        List.fold_left ~f ~init:Req.Set.empty reqs
      in
      Req.Set.elements reqs

  let applyResolutions resolutions (deps : t) =
    match deps with
    | OpamFormula deps ->
      let applyToDep (dep : Dep.t) =
        match PackageJson.Resolutions.find resolutions dep.name with
        | Some version ->
          let req =
            match version with
            | Version.Npm v -> Dep.Npm (SemverVersion.Constraint.EQ v)
            | Version.Opam v -> Dep.Opam (OpamPackageVersion.Constraint.EQ v)
            | Version.Source src -> Dep.Source (SourceSpec.ofSource src)
          in
          {dep with req}
        | None -> dep
      in
      let deps = List.map ~f:(List.map ~f:applyToDep) deps in
      OpamFormula deps
    | NpmFormula reqs ->
      let applyToReq (req : Req.t) =
        match PackageJson.Resolutions.find resolutions req.name with
        | Some version ->
          let spec = VersionSpec.ofVersion version in
          Req.make ~name:req.name ~spec
        | None -> req
      in
      let reqs = List.map ~f:applyToReq reqs in
      NpmFormula reqs

  let pp fmt deps =
    match deps with
    | OpamFormula deps ->
      let ppDisj fmt disj =
        match disj with
        | [] -> Fmt.unit "true" fmt ()
        | [dep] -> Dep.pp fmt dep
        | deps -> Fmt.pf fmt "(%a)" Fmt.(list ~sep:(unit " || ") Dep.pp) deps
      in
      Fmt.pf fmt "@[<h>[@;%a@;]@]" Fmt.(list ~sep:(unit " && ") ppDisj) deps
    | NpmFormula deps -> PackageJson.Dependencies.pp fmt deps

  let show deps =
    Format.asprintf "%a" pp deps
end

module File = struct
  [@@@ocaml.warning "-32"]
  type t = {
    name : Path.t;
    content : string;
    (* file, permissions add 0o644 default for backward compat. *)
    perm : (int [@default 0o644]);
  } [@@deriving (yojson, show, ord, eq)]
end

module OpamOverride = struct
  module Opam = struct
    [@@@ocaml.warning "-32"]
    type t = {
      source: (source option [@default None]);
      files: (File.t list [@default []]);
    } [@@deriving (yojson, eq, ord, show)]

    and source = {
      url: string;
      checksum: string;
    }

    let empty = {source = None; files = [];}

  end

  type t = {
    build: (PackageJson.CommandList.t [@default PackageJson.CommandList.empty]);
    install: (PackageJson.CommandList.t [@default PackageJson.CommandList.empty]);
    dependencies: (PackageJson.Dependencies.t [@default PackageJson.Dependencies.empty]);
    peerDependencies: (PackageJson.Dependencies.t [@default PackageJson.Dependencies.empty]) ;
    exportedEnv: (PackageJson.ExportedEnv.t [@default PackageJson.ExportedEnv.empty]);
    opam: (Opam.t [@default Opam.empty]);
  } [@@deriving (yojson, eq, ord, show)]

  let toString = show

  let empty =
    {
      build = PackageJson.CommandList.empty;
      install = PackageJson.CommandList.empty;
      dependencies = PackageJson.Dependencies.empty;
      peerDependencies = PackageJson.Dependencies.empty;
      exportedEnv = PackageJson.ExportedEnv.empty;
      opam = Opam.empty;
    }
end

module Opam = struct

  module OpamFile = struct
    type t = OpamFile.OPAM.t
    let pp fmt opam = Fmt.string fmt (OpamFile.OPAM.write_to_string opam)
    let to_yojson opam = `String (OpamFile.OPAM.write_to_string opam)
    let of_yojson = function
      | `String s -> Ok (OpamFile.OPAM.read_from_string s)
      | _ -> Error "expected string"
  end

  module OpamName = struct
    type t = OpamPackage.Name.t
    let pp fmt name = Fmt.string fmt (OpamPackage.Name.to_string name)
    let to_yojson name = `String (OpamPackage.Name.to_string name)
    let of_yojson = function
      | `String name -> Ok (OpamPackage.Name.of_string name)
      | _ -> Error "expected string"
  end

  module OpamPackageVersion = struct
    type t = OpamPackage.Version.t
    let pp fmt name = Fmt.string fmt (OpamPackage.Version.to_string name)
    let to_yojson name = `String (OpamPackage.Version.to_string name)
    let of_yojson = function
      | `String name -> Ok (OpamPackage.Version.of_string name)
      | _ -> Error "expected string"
  end

  type t = {
    name : OpamName.t;
    version : OpamPackageVersion.t;
    opam : OpamFile.t;
    files : unit -> File.t list RunAsync.t;
    override : OpamOverride.t;
  }
  [@@deriving show]
end

type t = {
  name : string;
  version : Version.t;
  originalVersion : Version.t option;
  source : source * source list;
  dependencies: Dependencies.t;
  devDependencies: Dependencies.t;
  opam : Opam.t option;
  kind : kind;
}

and source =
  | Source of Source.t
  | SourceSpec of SourceSpec.t

and kind =
  | Esy
  | Npm

let isOpamPackageName name =
  match String.cut ~sep:"/" name with
  | Some ("@opam", _) -> true
  | _ -> false

let pp fmt pkg =
  Fmt.pf fmt "%s@%a" pkg.name Version.pp pkg.version

let compare pkga pkgb =
  let name = String.compare pkga.name pkgb.name in
  if name = 0
  then Version.compare pkga.version pkgb.version
  else name

let ofPackageJson ~name ~version ~source (pkgJson : PackageJson.t) =
  let originalVersion =
    match pkgJson.version with
    | Some version -> Some (Version.Npm version)
    | None -> None
  in
  let dependencies =
    match pkgJson.esy with
    | None
    | Some {PackageJson.EsyPackageJson. _dependenciesForNewEsyInstaller= None} ->
      pkgJson.dependencies
    | Some {PackageJson.EsyPackageJson. _dependenciesForNewEsyInstaller= Some dependencies} ->
      dependencies
  in
  {
    name;
    version;
    originalVersion;
    dependencies = Dependencies.NpmFormula dependencies;
    devDependencies = Dependencies.NpmFormula pkgJson.devDependencies;
    source = source, [];
    opam = None;
    kind = if Option.isSome pkgJson.esy then Esy else Npm;
  }

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)
