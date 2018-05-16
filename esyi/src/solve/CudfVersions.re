open Shared;

type t = {
  lookupRealVersion: Hashtbl.t((string, int), Lockfile.realVersion),
  lookupIntVersion: Hashtbl.t((string, Lockfile.realVersion), int),
};

let init = () => {
  lookupRealVersion: Hashtbl.create(100),
  lookupIntVersion: Hashtbl.create(100),
};

let update = (t, name, realVersion, version) => {
  Hashtbl.replace(t.lookupIntVersion, (name, realVersion), version);
  Hashtbl.replace(t.lookupRealVersion, (name, version), realVersion);
};

let getRealVersion = (cudfVersions, package) => {
  switch (Hashtbl.find(cudfVersions.lookupRealVersion, (package.Cudf.package, package.Cudf.version))) {
  | exception Not_found => {
    failwith("Tried to find a package that wasn't listed in the versioncache " ++ package.Cudf.package ++ " " ++ string_of_int(package.Cudf.version))
  }
  | version => version
  };
};

let matchesSource = (source, cudfVersions, package) => {
  SolveUtils.satisfies(getRealVersion(cudfVersions, package), source)
};
