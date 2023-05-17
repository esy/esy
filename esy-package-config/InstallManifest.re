module String = Astring.String;

[@ocaml.warning "-32"];
[@deriving ord]
type disj('a) = list('a);
[@ocaml.warning "-32"];
[@deriving ord]
type conj('a) = list('a);

let isOpamPackageName = name =>
  switch (String.cut(~sep="/", name)) {
  | Some(("@opam", _)) => true
  | _ => false
  };

module Dep = {
  [@deriving ord]
  type t = {
    name: string,
    req,
  }
  and req =
    | Npm(SemverVersion.Constraint.t)
    | NpmDistTag(string)
    | Opam(OpamPackageVersion.Constraint.t)
    | Source(SourceSpec.t);

  let pp = (fmt, {name, req}) => {
    let ppReq = fmt =>
      fun
      | Npm(c) => SemverVersion.Constraint.pp(fmt, c)
      | NpmDistTag(tag) => Fmt.string(fmt, tag)
      | Opam(c) => OpamPackageVersion.Constraint.pp(fmt, c)
      | Source(src) => SourceSpec.pp(fmt, src);

    Fmt.pf(fmt, "%s@%a", name, ppReq, req);
  };
};

let yojson_of_reqs = (deps: list(Req.t)) => {
  let f = (x: Req.t) =>
    `List([`Assoc([(x.name, VersionSpec.to_yojson(x.spec))])]);
  `List(List.map(~f, deps));
};

module Dependencies = {
  [@deriving ord]
  type t =
    | OpamFormula(conj(disj(Dep.t)))
    | NpmFormula(NpmFormula.t);

  let toApproximateRequests =
    fun
    | NpmFormula(reqs) => reqs
    | OpamFormula(reqs) => {
        let reqs = {
          let f = (reqs, deps) => {
            let f = (reqs, dep: Dep.t) => {
              let spec =
                switch (dep.req) {
                | Dep.Npm(_) =>
                  VersionSpec.Npm([[SemverVersion.Constraint.ANY]])
                | Dep.NpmDistTag(tag) => VersionSpec.NpmDistTag(tag)
                | Dep.Opam(_) =>
                  VersionSpec.Opam([[OpamPackageVersion.Constraint.ANY]])
                | Dep.Source(srcSpec) => VersionSpec.Source(srcSpec)
                };

              Req.Set.add(Req.make(~name=dep.name, ~spec), reqs);
            };

            List.fold_left(~f, ~init=reqs, deps);
          };

          List.fold_left(~f, ~init=Req.Set.empty, reqs);
        };

        Req.Set.elements(reqs);
      };

  let pp = (fmt, deps) =>
    switch (deps) {
    | OpamFormula(deps) =>
      let ppDisj = (fmt, disj) =>
        switch (disj) {
        | [] => Fmt.any("true", fmt, ())
        | [dep] => Dep.pp(fmt, dep)
        | deps =>
          Fmt.pf(fmt, "(%a)", Fmt.(list(~sep=any(" || "), Dep.pp)), deps)
        };

      Fmt.pf(fmt, "@[<h>%a@]", Fmt.(list(~sep=any(" && "), ppDisj)), deps);
    | NpmFormula(deps) => NpmFormula.pp(fmt, deps)
    };

  let show = deps => Format.asprintf("%a", pp, deps);

  let filterDependenciesByName = (~name, deps) => {
    let findInNpmFormula = reqs => {
      let f = req => req.Req.name == name;
      List.filter(~f, reqs);
    };

    let findInOpamFormula = cnf => {
      let f = disj => {
        let f = dep => dep.Dep.name == name;
        List.exists(~f, disj);
      };

      List.filter(~f, cnf);
    };

    switch (deps) {
    | NpmFormula(f) => NpmFormula(findInNpmFormula(f))
    | OpamFormula(f) => OpamFormula(findInOpamFormula(f))
    };
  };

  let to_yojson =
    fun
    | NpmFormula(deps) => yojson_of_reqs(deps)
    | OpamFormula(deps) => {
        let ppReq = fmt => (
          fun
          | Dep.Npm(c) => SemverVersion.Constraint.pp(fmt, c)
          | Dep.NpmDistTag(tag) => Fmt.string(fmt, tag)
          | Dep.Opam(c) => OpamPackageVersion.Constraint.pp(fmt, c)
          | Dep.Source(src) => SourceSpec.pp(fmt, src)
        );

        let jsonOfItem = ({Dep.name, req}) =>
          `Assoc([(name, `String(Format.asprintf("%a", ppReq, req)))]);
        let f = disj => `List(List.map(~f=jsonOfItem, disj));
        `List(List.map(~f, deps));
      };
};

type t = {
  name: string,
  version: Version.t,
  originalVersion: option(Version.t),
  originalName: option(string),
  source: PackageSource.t,
  overrides: Overrides.t,
  dependencies: Dependencies.t,
  devDependencies: Dependencies.t,
  peerDependencies: NpmFormula.t,
  optDependencies: StringSet.t,
  resolutions: Resolutions.t,
  kind,
  installConfig: InstallConfig.t,
  extraSources: list(ExtraSource.t),
}
and kind =
  | Esy
  | Npm;

let pp = (fmt, pkg) =>
  Fmt.pf(fmt, "%s@%a", pkg.name, Version.pp, pkg.version);

let compare = (pkga, pkgb) => {
  let name = String.compare(pkga.name, pkgb.name);
  if (name == 0) {
    Version.compare(pkga.version, pkgb.version);
  } else {
    name;
  };
};

let to_yojson = pkg =>
  `Assoc([
    ("name", `String(pkg.name)),
    ("version", `String(Version.showSimple(pkg.version))),
    ("dependencies", Dependencies.to_yojson(pkg.dependencies)),
    ("devDependencies", Dependencies.to_yojson(pkg.devDependencies)),
    ("peerDependencies", yojson_of_reqs(pkg.peerDependencies)),
    (
      "optDependencies",
      `List(
        List.map(
          ~f=x => `String(x),
          StringSet.elements(pkg.optDependencies),
        ),
      ),
    ),
  ]);

module Map =
  Map.Make({
    type nonrec t = t;
    let compare = compare;
  });

module Set =
  Set.Make({
    type nonrec t = t;
    let compare = compare;
  });
