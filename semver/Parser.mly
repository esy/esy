%token <string> NUM
%token <string> WORD
%token <string> X
%token <string> V
%token DOT
%token PLUS
%token MINUS
%token OR
%token AND
%token DASH
%token STAR
%token TILDA
%token CARET
%token LT LTE GT GTE EQ
%token EOF

%start parse_version parse_formula
%type <Import.Version.t> parse_version
%type <Import.Formula.t> parse_formula

%{
  open Import.Version
  open Import.Formula
%}

%%

parse_version:
  v = version; EOF { v }

parse_formula:
  v = disj; EOF { v }

disj:
    v = range { [v] }
  | { [Conj [Patt Any]] }
  | v = range; disj_sep; vs = disj { v::vs }

disj_sep:
  OR { () }

range:
    v = separated_nonempty_list(AND, clause) { Conj v }
  | a = version_pattern; DASH; b = version_pattern { Hyphen (a, b) }

clause:
    v = version_pattern { Patt v }
  | EQ;    v = version_pattern { Expr (EQ, v) }
  | LT;    v = version_pattern { Expr (LT, v) }
  | GT;    v = version_pattern { Expr (GT, v) }
  | LTE;   v = version_pattern { Expr (LTE, v) }
  | GTE;   v = version_pattern { Expr (GTE, v) }
  | TILDA; v = version_pattern { Spec (Tilda, v) }
  | CARET; v = version_pattern { Spec (Caret, v) }

version_pattern:
    v = version { Version v }
  | star { Any }
  | ioption(V); major = num; DOT; minor = num { Minor (major, minor) }
  | ioption(V); major = num; DOT; minor = num; DOT; star { Minor (major, minor) }
  | ioption(V); major = num { Major major }
  | ioption(V); major = num; DOT; star { Major major }
  | ioption(V); major = num; DOT; star; DOT; star { Major major }

star:
    STAR { () }
  | X { () }


version:
  v = version_exact; p = loption(prerelease); b = loption(build) {
    let major, minor, patch = v in
    {major; minor; patch; prerelease = p; build = b}
  }

version_exact:
  ioption(V); major = num; DOT; minor = num; DOT; patch = num {
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
  | v = V { v }
  | v = X { v }
  | v = WORD { v }

alnum:
    v = al { v }
  | v = NUM { v }

alnums:
    v = alnum { v }
  | v = alnum; vs = alnums { v ^ vs }

%%
