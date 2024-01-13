type fetch;

type installation = {
  pkg: Package.t,
  packageJsonPath: Path.t,
  path: Path.t,
};

let fetch:
  (Sandbox.t, Package.t, option(string), option(string)) =>
  RunAsync.t(fetch);

let install: (Sandbox.t, fetch) => RunAsync.t(installation);
