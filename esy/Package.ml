module EsyBuild = struct
  type t = {
    buildCommands : Manifest.CommandList.t;
    installCommands : Manifest.CommandList.t;
    buildType : Manifest.BuildType.t;
    exportedEnv : Manifest.ExportedEnv.t;
  } [@@deriving (show, eq, ord)]
end

module OpamBuild = struct
  type t = OpamFile.OPAM.t

  let pp fmt _v =
    Fmt.pf fmt "<opam>"

  let equal = OpamFile.OPAM.equal

  let compare a b =
    if equal a b
    then 0
    else 1

end

type t = {
  id : string;
  name : string;
  version : string;
  dependencies : dependencies [@eq.skip];
  sourcePath : Config.ConfigPath.t [@skip];
  sourceType : Manifest.SourceType.t [@skip];
  sandboxEnv : Manifest.SandboxEnv.t [@skip];
  resolution : string option [@skip];
  build : build [@skip];
} [@@deriving (show, eq, ord)]

and build =
  | EsyBuild of EsyBuild.t
  | OpamBuild of OpamBuild.t

and dependencies =
  dependency list
  [@@deriving show]

and dependency =
  | Dependency of t
  | PeerDependency of t
  | OptDependency of t
  | DevDependency of t
  | BuildTimeDependency of t
  | InvalidDependency of {
    pkgName: string;
    reason: string;
  }

type pkg = t
type pkg_dependency = dependency

let packageOf (dep : dependency) = match dep with
| Dependency pkg
| PeerDependency pkg
| OptDependency pkg
| DevDependency pkg
| BuildTimeDependency pkg -> Some pkg
| InvalidDependency _ -> None

let readEsyManifest (path : Path.t) =
  let open RunAsync.Syntax in
  let%bind json = Fs.readJsonFile path in
  let%bind manifest = RunAsync.ofRun (Json.parseJsonWith Manifest.Esy.of_yojson json) in
  return manifest

let ofDir (path : Path.t) =
  let open RunAsync.Syntax in
  let esyJson = Path.(path / "esy.json") in
  let packageJson = Path.(path / "package.json") in
  (* let opam = Path.(path / "opam") in *)
  if%bind Fs.exists esyJson
  then
    let%bind manifest = readEsyManifest esyJson in
    return (Some (manifest, esyJson))
  else if%bind Fs.exists packageJson
  then
    let%bind manifest = readEsyManifest esyJson in
    return (Some (manifest, esyJson))
  else
    return None

module DependencyGraph = DependencyGraph.Make(struct

  type t = pkg

  let compare a b = compare a b

  module Dependency = struct
    type t = pkg_dependency
    let compare a b = compare_dependency a b
  end

  let id (pkg : t) = pkg.id

  let traverse pkg =
    let f acc dep = match dep with
      | Dependency pkg
      | OptDependency pkg
      | DevDependency pkg
      | BuildTimeDependency pkg
      | PeerDependency pkg -> (pkg, dep)::acc
      | InvalidDependency _ -> acc
    in
    pkg.dependencies
    |> List.fold_left ~f ~init:[]
    |> List.rev

end)

module DependencySet = Set.Make(struct
  type t = dependency
  let compare = compare_dependency
end)
