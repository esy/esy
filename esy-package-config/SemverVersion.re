module P = Parse;

module Version = {
  include Semver.Version;

  let prerelease = v =>
    switch (v.Semver.Version.prerelease, v.build) {
    | ([], []) => false
    | (_, _) => true
    };

  let stripPrerelease = v => Semver.Version.{...v, prerelease: [], build: []};

  let parseExn = Semver.Version.parse_exn;
  let parser = {
    open Parse;
    let%bind input = take_while1(_ => true);
    switch (Semver.Version.parse(input)) {
    | Ok(v) => return(v)
    | Error(msg) => fail(msg)
    };
  };

  let majorMinorPatch = v =>
    Some(Semver.Version.(v.major, v.minor, v.patch));
  let compare = Semver.Version.compare;

  let of_yojson = json =>
    switch (json) {
    | `String(v) => Semver.Version.parse(v)
    | _ => Error("expected string")
    };

  let to_yojson = v => `String(Semver.Version.show(v));
};

module Formula = {
  include Semver.Formula.DNF;
};
