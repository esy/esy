%token <string> NUM
%token <string> ALNUM
%token DOT
%token PLUS
%token MINUS
%token EOF

%start parse_version
%type <Types.version> parse_version

%{
  open Types
%}

%%

parse_version:
  v = version; EOF { v }

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
  v = preceded(PLUS, separated_nonempty_list(DOT, alnum)) { v }

prerelease:
  v = preceded(MINUS, separated_nonempty_list(DOT, prerelease_id)) { v }

prerelease_id:
    v = num { N v }
  | v = alnum { A v }

%inline num:
  v = NUM { int_of_string v }

alnum:
    v = ALNUM { v }
  | a = ALNUM; d = dashes; b = alnum { a ^ d ^ b }
  | a = ALNUM; d = dashes; b = NUM { a ^ d ^ b }
  | a = NUM; d = dashes; b = alnum { a ^ d ^ b }
  | a = NUM; d = dashes; b = NUM { a ^ d ^ b }

dashes:
    MINUS { "-" }
  | MINUS; v = dashes { "-" ^ v }

%%
