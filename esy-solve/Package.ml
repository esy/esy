open EsyPackageConfig
open EsyPackageConfig.PackageConfig

module String = Astring.String

[@@@ocaml.warning "-32"]
type 'a disj = 'a list [@@deriving ord]
[@@@ocaml.warning "-32"]
type 'a conj = 'a list [@@deriving ord]


let isOpamPackageName name =
  match String.cut ~sep:"/" name with
  | Some ("@opam", _) -> true
  | _ -> false

module Dep = struct
  type t = {
    name : string;
    req : req;
  } [@@deriving ord]

  and req =
    | Npm of SemverVersion.Constraint.t
    | NpmDistTag of string
    | Opam of OpamPackageVersion.Constraint.t
    | Source of SourceSpec.t

  let pp fmt {name; req;} =
    let ppReq fmt = function
      | Npm c -> SemverVersion.Constraint.pp fmt c
      | NpmDistTag tag -> Fmt.string fmt tag
      | Opam c -> OpamPackageVersion.Constraint.pp fmt c
      | Source src -> SourceSpec.pp fmt src
    in
    Fmt.pf fmt "%s@%a" name ppReq req

end

let yojson_of_reqs (deps : Req.t list) =
  let f (x : Req.t) = `List [`Assoc [x.name, (VersionSpec.to_yojson x.spec)]] in
  `List (List.map ~f deps)

module Dependencies = struct

  type t =
    | OpamFormula of Dep.t disj conj
    | NpmFormula of NpmFormula.t
    [@@deriving ord]

  let toApproximateRequests = function
    | NpmFormula reqs -> reqs
    | OpamFormula reqs ->
      let reqs =
        let f reqs deps =
          let f reqs (dep : Dep.t) =
            let spec =
              match dep.req with
              | Dep.Npm _ -> VersionSpec.Npm [[SemverVersion.Constraint.ANY]]
              | Dep.NpmDistTag tag -> VersionSpec.NpmDistTag tag
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

  let pp fmt deps =
    match deps with
    | OpamFormula deps ->
      let ppDisj fmt disj =
        match disj with
        | [] -> Fmt.unit "true" fmt ()
        | [dep] -> Dep.pp fmt dep
        | deps -> Fmt.pf fmt "(%a)" Fmt.(list ~sep:(unit " || ") Dep.pp) deps
      in
      Fmt.pf fmt "@[<h>%a@]" Fmt.(list ~sep:(unit " && ") ppDisj) deps
    | NpmFormula deps -> NpmFormula.pp fmt deps

  let show deps =
    Format.asprintf "%a" pp deps

  let filterDependenciesByName ~name deps =
    let findInNpmFormula reqs =
      let f req = req.Req.name = name in
      List.filter ~f reqs
    in
    let findInOpamFormula cnf =
      let f disj =
        let f dep = dep.Dep.name = name in
        List.exists ~f disj
      in
      List.filter ~f cnf
    in
    match deps with
    | NpmFormula f -> NpmFormula (findInNpmFormula f)
    | OpamFormula f -> OpamFormula (findInOpamFormula f)

  let to_yojson = function
    | NpmFormula deps -> yojson_of_reqs deps
    | OpamFormula deps ->
      let ppReq fmt = function
        | Dep.Npm c -> SemverVersion.Constraint.pp fmt c
        | Dep.NpmDistTag tag -> Fmt.string fmt tag
        | Dep.Opam c -> OpamPackageVersion.Constraint.pp fmt c
        | Dep.Source src -> SourceSpec.pp fmt src
      in
        let jsonOfItem {Dep. name; req;} = `Assoc [name, `String (Format.asprintf "%a" ppReq req)] in
        let f disj = `List (List.map ~f:jsonOfItem disj) in
          `List (List.map ~f deps)
end

type t = {
  name : string;
  version : Version.t;
  originalVersion : Version.t option;
  originalName : string option;
  source : PackageSource.t;
  overrides : Overrides.t;
  dependencies: Dependencies.t;
  devDependencies: Dependencies.t;
  peerDependencies: NpmFormula.t;
  optDependencies: StringSet.t;
  resolutions : PackageConfig.Resolutions.t;
  kind : kind;
}

and kind =
  | Esy
  | Npm

let pp fmt pkg =
  Fmt.pf fmt "%s@%a" pkg.name Version.pp pkg.version

let compare pkga pkgb =
  let name = String.compare pkga.name pkgb.name in
  if name = 0
  then Version.compare pkga.version pkgb.version
  else name

let to_yojson pkg =
  `Assoc [
    "name", `String pkg.name;
    "version", `String (Version.showSimple pkg.version);
    "dependencies", Dependencies.to_yojson pkg.dependencies;
    "devDependencies", Dependencies.to_yojson pkg.devDependencies;
    "peerDependencies", yojson_of_reqs pkg.peerDependencies;
    "optDependencies", `List (List.map ~f:(fun x -> `String x) (StringSet.elements pkg.optDependencies));
  ]

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)
