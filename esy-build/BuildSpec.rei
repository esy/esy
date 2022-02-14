/** This describes how a project should be built. */;
open DepSpec;
open EsyPackageConfig;

type t =
  EsyInstall.Solution.Spec.t = {
    all: FetchDepSpec.t,
    dev: FetchDepSpec.t,
  };

type mode =
  | Build
  | BuildDev;

let pp_mode: Fmt.t(mode);
let show_mode: mode => string;

let mode_to_yojson: Json.encoder(mode);
let mode_of_yojson: Json.decoder(mode);

let mode: (mode, EsyInstall.Package.t) => mode;
let depspec: (t, mode, EsyInstall.Package.t) => FetchDepSpec.t;
let buildCommands:
  (mode, EsyInstall.Package.t, BuildManifest.t) => BuildManifest.commands;
