%token <Import.Types.Version.t> VERSION
%token <Import.Types.Formula.pattern> PATTERN
%token <string> NUM
%token <string> WORD
%token DOT
%token PLUS
%token OR
%token AND
%token DASH
%token TILDA
%token CARET
%token LT LTE GT GTE EQ
%token EOF

%start parse_version parse_formula
%type <Import.Types.Version.t> parse_version
%type <Import.Types.Formula.t> parse_formula

%{
  open Import.Types.Version
  open Import.Types.Formula
%}

%%

parse_version:
  v = version; EOF { v }

parse_formula:
  v = disj; EOF { v }

disj:
    v = range { [v] }
  | { [Simple [Patt (Pattern Any)]] }
  | v = range; OR; vs = disj { v::vs }

range:
    v = separated_nonempty_list(AND, clause) { Simple v }
  | a = pattern; DASH; b = pattern { Hyphen (a, b) }

clause:
    v = pattern { Patt v }
  | EQ;    v = pattern { Expr (EQ, v) }
  | LT;    v = pattern { Expr (LT, v) }
  | GT;    v = pattern { Expr (GT, v) }
  | LTE;   v = pattern { Expr (LTE, v) }
  | GTE;   v = pattern { Expr (GTE, v) }
  | TILDA; v = pattern { Spec (Tilda, v) }
  | CARET; v = pattern { Spec (Caret, v) }

pattern:
    v = version { Version v }
  | p = PATTERN { Pattern p }

version:
  v = VERSION; p = loption(prerelease); b = loption(build) {
    {v with prerelease = p; build = b}
  }

build:
  v = preceded(PLUS, separated_nonempty_list(DOT, build_id)) { v }

prerelease:
  v = separated_nonempty_list(DOT, prerelease_id) { v }

prerelease_id:
    v = NUM { N (int_of_string v) }
  | v = WORD { A v }

build_id:
    v = NUM { v }
  | v = WORD { v }

%%
