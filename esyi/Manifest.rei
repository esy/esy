type t =
  | Opam(OpamFile.manifest)
  | PackageJson(PackageJson.t);

let name : t => string
let version : t => Solution.Version.t
let source : (t, Solution.Version.t) => Run.t(Types.PendingSource.t)
let dependencies : t => PackageJson.DependenciesInfo.t

/** TODO: Move this elsewhere */
module Github : {
  let getManifest : (string, string, option(string)) => Lwt.t(Run.t(t))
};
