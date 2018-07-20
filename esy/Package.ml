module EsyBuild = struct
  type t = {
    buildCommands : Manifest.CommandList.t;
    installCommands : Manifest.CommandList.t;
    buildType : Manifest.BuildType.t;
  } [@@deriving (show, ord, eq)]
end

module OpamBuild = struct
  type t = {
    name : string;
    version : string;
    buildCommands : Manifest.Opam.commands;
    installCommands : Manifest.Opam.commands;
    patches : (OpamFilename.Base.t * OpamTypes.filter option) list;
    substs : OpamFilename.Base.t list;
    buildType : Manifest.BuildType.t;
  }

  let pp fmt _v = Fmt.pf fmt "<opam>"
  let compare _a _b = 0
  let equal _a _b = false
end

type t = {
  id : string;
  name : string;
  version : string;
  dependencies : dependencies;
  sourcePath : Config.ConfigPath.t;
  sourceType : Manifest.SourceType.t;
  sandboxEnv : Manifest.SandboxEnv.t;
  exportedEnv : Manifest.ExportedEnv.t;
  resolution : string option;
  build : build;
} [@@deriving (show, ord, eq)]

and build =
  | EsyBuild of EsyBuild.t
  | OpamBuild of OpamBuild.t

and dependencies =
  dependency list

and dependency =
  | Dependency of t
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
| OptDependency pkg
| DevDependency pkg
| BuildTimeDependency pkg -> Some pkg
| InvalidDependency _ -> None

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
      | BuildTimeDependency pkg -> (pkg, dep)::acc
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
