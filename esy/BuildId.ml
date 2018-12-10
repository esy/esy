module PackageId = EsyInstall.PackageId
module Dist = EsyInstall.Dist
module Version = EsyInstall.Version

type t = string

let make ~sandboxEnv ~id ~dist ~build ~sourceType ~mode ~dependencies () =

  let commands =
    match mode, sourceType, build.BuildManifest.buildDev with
    | BuildSpec.Build, _, _
    | BuildSpec.BuildDev, (BuildManifest.SourceType.ImmutableWithTransientDependencies | Immutable), _
    | BuildSpec.BuildDev, Transient, None ->
      build.BuildManifest.build
    | BuildSpec.BuildDev, BuildManifest.SourceType.Transient, Some commands ->
      BuildManifest.EsyCommands commands
  in

  let hash =

    (* include ids of dependencies *)
    let dependencies = List.sort ~cmp:String.compare dependencies in

    (* include parts of the current package metadata which contribute to the
      * build commands/environment *)
    let self =
      build
      |> BuildManifest.to_yojson
      |> Yojson.Safe.to_string
    in

    let commands =
      commands
      |> BuildManifest.commands_to_yojson
      |> Yojson.Safe.to_string
    in

    (* a special tag which is communicated by the installer and specifies
      * the version of distribution of vcs commit sha *)
    let dist =
      match dist with
      | Some dist -> Dist.show dist
      | None -> "-"
    in

    let sandboxEnv =
      sandboxEnv
      |> BuildManifest.Env.to_yojson
      |> Yojson.Safe.to_string
    in

    String.concat "__" (
      (PackageId.show id)
      ::sandboxEnv
      ::dist
      ::self
      ::(BuildSpec.show_mode mode)
      ::commands::dependencies)
    |> Digest.string
    |> Digest.to_hex
    |> fun hash -> String.sub hash 0 8
  in

  let name = PackageId.name id in
  let version = PackageId.version id in

  match version with
  | Version.Npm _
  | Version.Opam _ ->
    Printf.sprintf "%s-%s-%s"
      (Path.safeSeg name)
      (Path.safePath (Version.show version))
      hash
  | Version.Source _ ->
    Printf.sprintf "%s-%s"
      (Path.safeSeg name)
      hash

let pp = Fmt.string
let show v = v
let compare = String.compare
let to_yojson = Json.Encode.string
let of_yojson = Json.Decode.string

module Set = StringSet
