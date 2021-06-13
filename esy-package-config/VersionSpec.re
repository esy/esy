[@deriving ord]
type t =
  | Npm(SemverVersion.Formula.DNF.t)
  | NpmDistTag(string)
  | Opam(OpamPackageVersion.Formula.DNF.t)
  | Source(SourceSpec.t);

let show =
  fun
  | Npm(formula) => SemverVersion.Formula.DNF.show(formula)
  | NpmDistTag(tag) => tag
  | Opam(formula) => OpamPackageVersion.Formula.DNF.show(formula)
  | Source(src) => SourceSpec.show(src);

let pp = (fmt, spec) => Fmt.string(fmt, show(spec));

let to_yojson = src => `String(show(src));

let ofVersion = (version: Version.t) =>
  switch (version) {
  | Version.Npm(v) =>
    Npm(SemverVersion.Formula.DNF.unit(SemverVersion.Constraint.EQ(v)))
  | Version.Opam(v) =>
    Opam(
      OpamPackageVersion.Formula.DNF.unit(
        OpamPackageVersion.Constraint.EQ(v),
      ),
    )
  | Version.Source(src) =>
    let srcSpec = SourceSpec.ofSource(src);
    Source(srcSpec);
  };

module Parse = {
  include Parse;

  let npmDistTag = {
    /* npm dist tags can be any strings which cannot be npm version ranges,
     * this is a simplified check for that. */
    let p = {
      let%map tag = take_while1(_ => true);
      NpmDistTag(tag);
    };

    switch%bind (peek_char_fail) {
    | 'v'
    | '0' .. '9' => fail("unable to parse npm tag")
    | _ => p
    };
  };

  let sourceSpec = {
    let%map sourceSpec = SourceSpec.parser;
    Source(sourceSpec);
  };

  let opamConstraint = {
    let* spec = take_while1(_ => true);
    switch (OpamPackageVersion.Formula.parse(spec)) {
    | Ok(v) => return(Opam(v))
    | Error(msg) => fail(msg)
    };
  };

  let npmAnyConstraint = return(Npm([[SemverVersion.Constraint.ANY]]));

  let npmConstraint = {
    let* spec = take_while1(_ => true);
    switch (SemverVersion.Formula.parse(spec)) {
    | Ok(v) => return(Npm(v))
    | Error(msg) => fail(msg)
    };
  };

  let npmWithProto = {
    let prefix = string("npm:");
    let withName = take_while1(c => c != '@') *> char('@') *> npmConstraint;
    let withoutName = npmConstraint;
    prefix *> (withName <|> withoutName);
  };

  let parserOpam = sourceSpec <|> opamConstraint;

  let parserNpm =
    sourceSpec
    <|> npmWithProto
    <|> npmConstraint
    <|> npmDistTag
    <|> npmAnyConstraint;
};

let parserNpm = Parse.parserNpm;
let parserOpam = Parse.parserOpam;
