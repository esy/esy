open Sexplib0.Sexp_conv;

[@deriving (ord, sexp_of)]
type t = (kind, string)
and kind =
  | Md5
  | Sha1
  | Sha256
  | Sha512;

let name = ((kind, _)) =>
  switch (kind) {
  | Md5 => "md5"
  | Sha1 => "sha1"
  | Sha256 => "sha256"
  | Sha512 => "sha512"
  };

let pp = (fmt, v) =>
  switch (v) {
  | (Md5, v) => Fmt.pf(fmt, "md5:%s", v)
  | (Sha1, v) => Fmt.pf(fmt, "sha1:%s", v)
  | (Sha256, v) => Fmt.pf(fmt, "sha256:%s", v)
  | (Sha512, v) => Fmt.pf(fmt, "sha512:%s", v)
  };

let show = v =>
  switch (v) {
  | (Md5, v) => "md5:" ++ v
  | (Sha1, v) => "sha1:" ++ v
  | (Sha256, v) => "sha256:" ++ v
  | (Sha512, v) => "sha512:" ++ v
  };

let parser = {
  open Parse;
  let md5 = ignore(string("md5")) <* char(':') >>| (() => Md5);
  let sha1 = ignore(string("sha1") <* char(':')) >>| (() => Sha1);
  let sha256 = ignore(string("sha256") <* char(':')) >>| (() => Sha256);
  let sha512 = ignore(string("sha512") <* char(':')) >>| (() => Sha512);
  let kind = md5 <|> sha1 <|> sha256 <|> sha512 <?> "kind";
  pair(option(Sha1, kind), hex) <?> "checksum";
};

let parse = Parse.parse(parser);

let to_yojson = v => `String(show(v));
let of_yojson = json =>
  switch (json) {
  | `String(v) => parse(v)
  | _ => Error("expected string")
  };

let md5sum =
  switch (System.Platform.host) {
  | System.Platform.Unix
  | System.Platform.Darwin => Cmd.(v("md5") % "-q")
  | System.Platform.Linux
  | System.Platform.Cygwin
  | System.Platform.Windows
  | System.Platform.Unknown => Cmd.(v("md5sum"))
  };
let sha1sum = Cmd.(v("shasum") % "--algorithm" % "1");
let sha256sum = Cmd.(v("shasum") % "--algorithm" % "256");
let sha512sum = Cmd.(v("shasum") % "--algorithm" % "512");

let computeOfFile = (~kind=Sha256, path) => {
  let cmd =
    switch (kind) {
    | Md5 => md5sum
    | Sha1 => sha1sum
    | Sha256 => sha256sum
    | Sha512 => sha512sum
    };

  /* On Windows, the checksum tools packaged with Cygwin require cygwin-style paths */
  RunAsync.ofBosError(
    {
      open Result.Syntax;
      let path = EsyBash.normalizePathForCygwin(Path.show(path));
      let* out = EsyBash.runOut(Cmd.(cmd % path |> toBosCmd));
      switch (Astring.String.cut(~sep=" ", out)) {
      | Some((v, _)) => return((kind, v))
      | None => return((kind, String.trim(out)))
      };
    },
  );
};

let checkFile = (~path, checksum: t) => {
  open RunAsync.Syntax;

  let* value = {
    let cmd =
      switch (checksum) {
      | (Md5, _) => md5sum
      | (Sha1, _) => sha1sum
      | (Sha256, _) => sha256sum
      | (Sha512, _) => sha512sum
      };

    /* On Windows, the checksum tools packaged with Cygwin require cygwin-style paths */
    RunAsync.ofBosError(
      {
        open Result.Syntax;
        let path = EsyBash.normalizePathForCygwin(Path.show(path));
        let* out = EsyBash.runOut(Cmd.(cmd % path |> toBosCmd));
        switch (Astring.String.cut(~sep=" ", out)) {
        | Some((v, _)) => return(v)
        | None => return(String.trim(out))
        };
      },
    );
  };

  let (_, cvalue) = checksum;
  if (cvalue == value) {
    return();
  } else {
    let msg =
      Printf.sprintf(
        "%s checksum mismatch: expected %s but got %s",
        name(checksum),
        cvalue,
        value,
      );

    error(msg);
  };
};
