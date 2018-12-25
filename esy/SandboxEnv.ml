open EsyPackageConfig

type t = BuildEnv.t

let empty = BuildEnv.empty

let to_yojson = BuildEnv.to_yojson
let of_yojson = BuildEnv.of_yojson

module OfPackageJson = struct
  type esy = {
    sandboxEnv : BuildEnv.t [@default BuildEnv.empty];
  } [@@deriving of_yojson { strict = false }]

  type t = {
    esy : esy [@default {sandboxEnv = BuildEnv.empty}]
  } [@@deriving of_yojson { strict = false }]

end

let ofSandbox spec =
  let open RunAsync.Syntax in
  match spec.EsyInstall.SandboxSpec.manifest with

  | EsyInstall.SandboxSpec.Manifest (Esy, filename) ->
    let%bind json = Fs.readJsonFile Path.(spec.path / filename) in
    let%bind pkgJson = RunAsync.ofRun (Json.parseJsonWith OfPackageJson.of_yojson json) in
    return pkgJson.OfPackageJson.esy.sandboxEnv

  | EsyInstall.SandboxSpec.Manifest (Opam, _)
  | EsyInstall.SandboxSpec.ManifestAggregate _ ->
    return BuildEnv.empty
