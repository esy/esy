type t = BuildManifest.Env.t

let empty = BuildManifest.Env.empty

let to_yojson = BuildManifest.Env.to_yojson
let of_yojson = BuildManifest.Env.of_yojson

module OfPackageJson = struct
  type esy = {
    sandboxEnv : BuildManifest.Env.t [@default BuildManifest.Env.empty];
  } [@@deriving of_yojson { strict = false }]

  type t = {
    esy : esy [@default {sandboxEnv = BuildManifest.Env.empty}]
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
    return BuildManifest.Env.empty
