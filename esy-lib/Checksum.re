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

let rec foldFile = (f, init, ic) => {
  let buf = Bytes.create(4096);
  let read = input(ic, buf, 0, 4096);
  if (read == 0) {
    init;
  } else {
    foldFile(f, f(init, buf, 0, read), ic);
  };
};

let hashFile = (filename, m: (module Digestif.S)) => {
  module M = (val m);
  let ic = open_in_bin(filename);
  let ctx = M.empty;
  let f = (ctx, buf, off, len) => M.feed_bytes(ctx, ~off, ~len, buf);
  let ctx = foldFile(f, ctx, ic);
  let hash = M.get(ctx);
  M.to_hex(hash);
};

let hashOfPath = (path, kind) => {
  let filename = Fpath.to_string(path);
  switch (kind) {
  | Md5 => hashFile(filename, (module Digestif.MD5))
  | Sha1 => hashFile(filename, (module Digestif.SHA1))
  | Sha256 => hashFile(filename, (module Digestif.SHA256))
  | Sha512 => hashFile(filename, (module Digestif.SHA3_512))
  };
};

let computeOfFile = (~kind=Sha256, path) => {
  let hash = hashOfPath(path, kind);
  RunAsync.return((kind, hash));
};

let checkFile = (~path, checksum: t) => {
  open RunAsync.Syntax;

  let (kind, cvalue) = checksum;
  let value = hashOfPath(path, kind);

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
