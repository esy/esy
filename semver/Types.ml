type version = {
  major : int;
  minor : int;
  patch : int;
  prerelease : prerelease_id list;
  build : string list;
}

and prerelease_id =
  | N of int
  | A of string

type version_pattern =
  | Any
  | Major of {major : int;}
  | Minor of {major : int; minor : int;}
  | Version of version

type op =
 | GT
 | GTE
 | LT
 | LTE
 | EQ

type 'v conj = 'v list
type 'v disj = 'v list
type 'v dnf = (op * 'v) conj disj

type formula = version_pattern dnf

type simple_formula = version dnf
