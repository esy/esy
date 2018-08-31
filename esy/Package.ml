type t = {
  id : string;
  name : string;
  version : string;
  dependencies : dependencies;
  build : ((Manifest.Build.t [@equal fun _ _ -> true]) [@compare fun _ _ -> 0]);
  sourcePath : Config.Path.t;
  resolution : string option;
}

and dependencies =
  dependency list

and dependency =
  | Dependency of t
  | OptDependency of t
  | DevDependency of t
  | BuildTimeDependency of t
  | InvalidDependency of {
    name: string;
    reason: [ | `Reason of string | `Missing ];
  }

let compare a b = String.compare a.id b.id
let compare_dependency a b =
  match a, b with
  | Dependency a, Dependency b -> compare a b
  | OptDependency a, OptDependency b -> compare a b
  | BuildTimeDependency a, BuildTimeDependency b -> compare a b
  | DevDependency a, DevDependency b -> compare a b
  | InvalidDependency a, InvalidDependency b -> String.compare a.name b.name
  | Dependency _, _ -> 1
  | OptDependency _, Dependency _ -> -1
  | OptDependency _, _ -> 1
  | BuildTimeDependency _, Dependency _ -> -1
  | BuildTimeDependency _, OptDependency _ -> -1
  | BuildTimeDependency _, _ -> 1
  | DevDependency _, Dependency _ -> -1
  | DevDependency _, OptDependency _ -> -1
  | DevDependency _, BuildTimeDependency _ -> -1
  | DevDependency _, _ -> 1
  | InvalidDependency _, _ -> -1

let pp_dependency fmt dep =
  match dep with
  | Dependency p -> Fmt.pf fmt "Dependency %s" p.id
  | OptDependency p -> Fmt.pf fmt "OptDependency %s" p.id
  | DevDependency p -> Fmt.pf fmt "DevDependency %s" p.id
  | BuildTimeDependency p -> Fmt.pf fmt "BuildTimeDependency %s" p.id
  | InvalidDependency p -> Fmt.pf fmt "InvalidDependency %s" p.name

type pkg = t
type pkg_dependency = dependency

let packageOf (dep : dependency) = match dep with
| Dependency pkg
| OptDependency pkg
| DevDependency pkg
| BuildTimeDependency pkg -> Some pkg
| InvalidDependency _ -> None

module Graph = DependencyGraph.Make(struct

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

module DependencyMap = Map.Make(struct
  type t = dependency
  let compare = compare_dependency
end)

module Map = Map.Make(struct
  type t = pkg
  let compare = compare
end)
