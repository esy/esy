open EsyInstall;

type t =
  | ByPkgSpec(PkgSpec.t)
  | ByPath(Path.t);

let pp = fmt =>
  fun
  | ByPkgSpec(spec) => PkgSpec.pp(fmt, spec)
  | ByPath(path) => Path.pp(fmt, path);

let parse = v =>
  Result.Syntax.(
    if (Sys.file_exists(v) && !Sys.is_directory(v)) {
      return(ByPath(Path.v(v)));
    } else {
      let%map pkgspec = PkgSpec.parse(v);
      ByPkgSpec(pkgspec);
    }
  );

let root = ByPkgSpec(Root);

let conv = {
  open Cmdliner;
  let parse = v => Rresult.R.error_to_msg(~pp_error=Fmt.string, parse(v));
  Arg.conv(~docv="PACKAGE", (parse, pp));
};
