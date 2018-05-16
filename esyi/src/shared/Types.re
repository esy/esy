
[@deriving yojson]
type npmConcrete = (int, int, int, option(string));

type alpha = Alpha(string, option(num))
and num = Num(int, option(alpha));

let alpha_to_yojson = (Alpha(text, num)) => {
  let rec lnum = num => switch num {
  | None => []
  | Some(Num(n, a)) => [`Int(n), ...lalpha(a)]
  } and lalpha = alpha => switch alpha {
  | None => []
  | Some(Alpha(a, n)) => [`String(a), ...lnum(n)]
  };
  `List([`String(text), ...(lnum(num))])
};

let module ResultInfix = {
  let (|!>) = (item, fn) => switch item {
  | Result.Ok(value) => fn(value)
  | Error(e) => Result.Error(e)
  };
  let (|!>>) = (item, fn) => switch item {
  | Result.Ok(value) => Result.Ok(fn(value))
  | Error(e) => Result.Error(e)
  };
  let ok = v => Result.Ok(v);
  let fail = v => Result.Error(v);
};

let alpha_of_yojson = (json) => switch json {
| `List(items) => {
  open ResultInfix;
  let rec lnum = items => switch items {
  | [] => ok(None)
  | [`Int(n), ...rest] => lalpha(rest) |!>> r => Some(Num(n, r))
  | _ => fail("Num should be a number")
  } and lalpha = items => switch items {
  | [] => ok(None)
  | [`String(n), ...rest] => lnum(rest) |!>> r => Some(Alpha(n, r))
  | _ => fail("Alpha should be string")
  };
  lalpha(items) |!> v => switch v {
  | None => fail("No alpha")
  | Some(v) => ok(v)
  };
}
| _ => Result.Error("Alpha should be a list")
};

[@deriving yojson]
type opamConcrete = alpha;

[@deriving yojson]
type opamRange = GenericVersion.range(opamConcrete);
[@deriving yojson]
type npmRange = GenericVersion.range(npmConcrete);

let viewNpmConcrete = ((m, i, p, r)) => {
  ([m, i, p] |> List.map(string_of_int) |> String.concat("."))
  ++
  switch r { | None => "" | Some(a) => a}
};

let rec viewOpamConcrete = (Alpha(a, na)) => {
  switch na {
  | None => a
  | Some(b) => a ++ viewNum(b)
  }
} and viewNum = (Num(a, na)) => {
  string_of_int(a) ++ switch na {
  | None => ""
  | Some(a) => viewOpamConcrete(a)
  }
};

type json = Yojson.Safe.json;
let json_to_yojson = x => x;
let json_of_yojson = x => Result.Ok(x);

[@deriving yojson]
type opamFile = (json, list((string, string)), list(string));

module PendingSource = {
  [@deriving yojson]
  type t =
    | WithOpamFile(t, opamFile)
    /* url & checksum */
    | Archive(string, option(string))
    /* url & ref */
    | GitSource(string, option(string))
    | GithubSource(string, string, option(string))
    | File(string)
    | NoSource;
};

/** Lock that down */
module Source = {
  [@deriving yojson]
  type inner =
    /* url & checksum */
    | Archive(string, string)
    /* url & commit */
    | GitSource(string, string)
    | GithubSource(string, string, string)
    | File(string)
    | NoSource;
  [@deriving yojson]
  type t = (inner, option(opamFile));
};

[@deriving yojson]
type requestedDep =
  | Npm(GenericVersion.range(npmConcrete))
  | Github(string, string, option(string)) /* user, repo, ref (branch/tag/commit) */
  | Opam(GenericVersion.range(opamConcrete)) /* opam allows a bunch of weird stuff. for now I'm just doing semver */
  | Git(string)
  ;

let resolvedPrefix = "esyi5-";

[@deriving yojson]
type dep = (string, requestedDep);

[@deriving yojson]
type depsByKind = {
  runtime: list(dep),
  dev: list(dep),
  build: list(dep),
  /* This is for npm deps of an esy package. npm deps of an npm package are classified as "runtime". */
  npm: list(dep),
  /* TODO targets or something */
};

let viewReq = req => switch req {
| Github(org, repo, ref) => "github: " ++ org ++ "/" ++ repo
| Git(s) => "git: " ++ s
| Npm(t) => "npm: " ++ GenericVersion.view(viewNpmConcrete, t)
| Opam(t) => "opam: " ++ GenericVersion.view(viewOpamConcrete, t)
};

type config = {
  esyOpamOverrides: string,
  opamRepository: string,
  baseDirectory: string,
};


let opamFromNpmConcrete = ((major, minor, patch, rest)) => {
  Alpha("",
    Some(
      Num(major, Some(Alpha(".", Some(
        Num(minor, Some(Alpha(".", Some(
          Num(patch, switch rest {
          | None => None
          | Some(rest) => Some(Alpha(rest, None))
          })
        ))))
      ))))
    )
  )
};
