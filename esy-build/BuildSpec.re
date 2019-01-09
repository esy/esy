open EsyPackageConfig;
module Package = EsyInstall.Package;

type t =
  EsyInstall.Solution.Spec.t = {
    all: EsyInstall.Solution.DepSpec.t,
    dev: EsyInstall.Solution.DepSpec.t,
  };

type mode =
  | Build
  | BuildDev;

let show_mode =
  fun
  | Build => "build"
  | BuildDev => "buildDev";

let pp_mode = (fmt, mode) => Fmt.string(fmt, show_mode(mode));

let mode_to_yojson =
  fun
  | Build => `String("build")
  | BuildDev => `String("buildDev");

let mode_of_yojson =
  fun
  | `String("build") => Ok(Build)
  | `String("buildDev") => Ok(BuildDev)
  | _json =>
    Result.errorf({|invalid BuildSpec.mode: expected "build" or "buildDev"|});

let mode = (mode, pkg) =>
  switch (pkg.Package.source, mode) {
  | (Link({kind: LinkDev, _}), BuildDev) => BuildDev
  | (Link({kind: LinkDev, _}), Build)
  | (Link({kind: LinkRegular, _}), _)
  | (Install(_), _) => Build
  };

let depspec = (spec, mode, pkg) =>
  switch (pkg.Package.source, mode) {
  | (Link({kind: LinkDev, _}), BuildDev) => spec.dev
  | (Link({kind: LinkDev, _}), Build)
  | (Link({kind: LinkRegular, _}), _)
  | (Install(_), _) => spec.all
  };

let buildCommands = (mode, pkg, build: BuildManifest.t) =>
  switch (pkg.Package.source, mode) {
  | (Link({kind: LinkDev, _}), BuildDev) =>
    switch (build.buildDev) {
    | Some(buildDev) => BuildManifest.EsyCommands(buildDev)
    | None => build.build
    }
  | (Link({kind: LinkDev, _}), Build)
  | (Link({kind: LinkRegular, _}), _)
  | (Install(_), _) => build.build
  };
