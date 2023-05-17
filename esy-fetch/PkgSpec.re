open EsyPackageConfig;

type t =
  | Root
  | ByName(string)
  | ByNameVersion((string, Version.t))
  | ById(PackageId.t);

let pp = fmt =>
  fun
  | Root => Fmt.any("root", fmt, ())
  | ByName(name) => Fmt.string(fmt, name)
  | [@implicit_arity] ByNameVersion(name, version) =>
    Fmt.pf(fmt, "%s@%a", name, Version.pp, version)
  | ById(id) => PackageId.pp(fmt, id);

let matches = (rootid, pkgspec, pkgid) =>
  switch (pkgspec) {
  | Root => PackageId.compare(rootid, pkgid) == 0
  | ByName(name) => String.compare(name, PackageId.name(pkgid)) == 0
  | [@implicit_arity] ByNameVersion(name, version) =>
    String.compare(name, PackageId.name(pkgid)) == 0
    && Version.compare(version, PackageId.version(pkgid)) == 0
  | ById(id) => PackageId.compare(id, pkgid) == 0
  };

let parse =
  Result.Syntax.(
    fun
    | "root" => return(Root)
    | v => {
        let split = Astring.String.cut(~sep="@");
        let rec parsename = v =>
          switch (split(v)) {
          | Some(("", v)) =>
            let (name, rest) = parsename(v);
            ("@" ++ name, rest);
          | Some((name, rest)) => (name, Some(rest))
          | None => (v, None)
          };

        switch (parsename(v)) {
        | (name, Some(""))
        | (name, None) => return(ByName(name))
        | (name, Some(rest)) =>
          switch (split(rest)) {
          | Some(_) =>
            let* id = PackageId.parse(v);
            return(ById(id));
          | None =>
            let* version = Version.parse(rest);
            return([@implicit_arity] ByNameVersion(name, version));
          }
        };
      }
  );

let of_yojson = json =>
  switch (json) {
  | `String(v) => parse(v)
  | _ => Error("PkgSpec: expected a string")
  };
