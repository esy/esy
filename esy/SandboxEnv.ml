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
  match spec.EsyI.SandboxSpec.manifest with

  | EsyI.ManifestSpec.One (EsyI.ManifestSpec.Filename.Esy, filename) ->
    let%bind json = Fs.readJsonFile Path.(spec.path / filename) in
    let%bind pkgJson = RunAsync.ofRun (Json.parseJsonWith OfPackageJson.of_yojson json) in
    return pkgJson.OfPackageJson.esy.sandboxEnv

  | EsyI.ManifestSpec.One (EsyI.ManifestSpec.Filename.Opam, _)
  | EsyI.ManifestSpec.ManyOpam ->
    return BuildManifest.Env.empty
