%token <string> NUM
%token <string> ALNUM
%token DOT
%token PLUS
%token MINUS
%token OR
%token DASH
%token STAR
%token <string> X
%token TILDA
%token CARET
%token WS
%token LT LTE GT GTE EQ
%token EOF

%start parse_version parse_formula
%type <Types.Version.t> parse_version
%type <Types.Formula.t> parse_formula

%{
  open Types.Version
  open Types.Formula
%}

%%

parse_version:
  v = version; EOF { v }

parse_formula:
  v = disj; EOF { v }

disj:
    v = range { [v] }
  | { [Conj [Patt Any]] }
  | v = range; OR; vs = disj { v::vs }

range:
    v = separated_nonempty_list(WS, clause) { Conj v }
  | a = version_pattern; DASH; b = version_pattern { Hyphen (a, b) }

clause:
    v = version_pattern { Patt v }
  | EQ;  WS?; v = version_pattern { Expr (EQ, v) }
  | LT;  WS?; v = version_pattern { Expr (LT, v) }
  | GT;  WS?; v = version_pattern { Expr (GT, v) }
  | LTE; WS?; v = version_pattern { Expr (LTE, v) }
  | GTE; WS?; v = version_pattern { Expr (GTE, v) }
  | TILDA; v = version_pattern { Spec (Tilda, v) }
  | CARET; v = version_pattern { Spec (Caret, v) }

version_pattern:
    v = version { Version v }
  | star { Any }
  | major = num; DOT; minor = num { Minor (major, minor) }
  | major = num; DOT; minor = num; DOT; star { Minor (major, minor) }
  | major = num { Major major }
  | major = num; DOT; star { Major major }
  | major = num; DOT; star; DOT; star { Major major }

star:
    STAR { () }
  | X { () }

version:
  v = version_exact; p = loption(prerelease); b = loption(build) {
    let major, minor, patch = v in
    {major; minor; patch; prerelease = p; build = b}
  }

version_exact:
  major = num; DOT; minor = num; DOT; patch = num {
    major, minor, patch
  }

build:
  v = preceded(PLUS, separated_nonempty_list(DOT, word)) { v }

prerelease:
  v = preceded(MINUS, separated_nonempty_list(DOT, prerelease_id)) { v }

prerelease_id:
    v = num { N v }
  | v = word { A v }

num:
  v = NUM { int_of_string v }

word:
    v = al { v }
  | v = alnum; vs = alnums { v ^ vs }

al:
    MINUS { "-" }
  | v = X { v }
  | v = ALNUM { v }

alnum:
    v = al { v }
  | v = NUM { v }

alnums:
    v = alnum { v }
  | v = alnum; vs = alnums { v ^ vs }

%%
