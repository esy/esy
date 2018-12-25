open EsyPackageConfig

type t = PackageConfig.Env.t

let empty = PackageConfig.Env.empty

let to_yojson = PackageConfig.Env.to_yojson
let of_yojson = PackageConfig.Env.of_yojson

module OfPackageJson = struct
  type esy = {
    sandboxEnv : PackageConfig.Env.t [@default PackageConfig.Env.empty];
  } [@@deriving of_yojson { strict = false }]

  type t = {
    esy : esy [@default {sandboxEnv = PackageConfig.Env.empty}]
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
    return PackageConfig.Env.empty
