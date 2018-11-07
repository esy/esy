module OpamPackageName = struct
  type t = OpamPackage.Name.t
  let to_yojson name = `String (OpamPackage.Name.to_string name)
  let of_yojson = function
    | `String name -> Ok (OpamPackage.Name.of_string name)
    | _ -> Error "expected string"
end

module OpamPackageVersion = struct
  type t = OpamPackage.Version.t
  let to_yojson name = `String (OpamPackage.Version.to_string name)
  let of_yojson = function
    | `String name -> Ok (OpamPackage.Version.of_string name)
    | _ -> Error "expected string"
end

type t = {
  name : OpamPackageName.t;
  version : OpamPackageVersion.t;
  path : Path.t;
} [@@deriving yojson]

module Lock = struct
  type nonrec t = t

  let of_yojson = of_yojson
  let to_yojson = to_yojson
end

let toLock ~sandbox opam =
  let open RunAsync.Syntax in
  let sandboxPath = sandbox.SandboxSpec.path in
  let opampath = Path.(sandboxPath // opam.path) in
  let dst =
    let name = OpamPackage.Name.to_string opam.name in
    let version = OpamPackage.Version.to_string opam.version in
    Path.(SandboxSpec.solutionLockPath sandbox / "opam" / (name ^ "." ^ version))
  in
  if Path.isPrefix sandboxPath opampath
  then return opam
  else (
    let%bind () = Fs.copyPath ~src:opam.path ~dst in
    return {opam with path = Path.tryRelativize ~root:sandboxPath dst;}
  )

let ofLock ~sandbox opam =
  let open RunAsync.Syntax in
  let sandboxPath = sandbox.SandboxSpec.path in
  let opampath = Path.(sandboxPath // opam.path) in
  return {opam with path = opampath;}
