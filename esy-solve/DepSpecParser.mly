%token <string> ID
%token PLUS
%token LPAREN
%token RPAREN
%token EOF

%left PLUS

%{

%}

%start start
%type <DepSpecBase.t> start

%%

start:
  e = expr; EOF { e }

expr:
    e = select { e }
  | e = package { e }
  | e = union { e }

id:
  id = ID; {
    match id with
    | "self" -> DepSpecBase.self
    | _ -> $syntaxerror
  }

package:
  id = ID; {
    match id with
    | "self" -> DepSpecBase.(package self)
    | _ -> $syntaxerror
  }

select:
  select = ID; LPAREN; id = id; RPAREN {
    match select with
    | "dependencies" -> DepSpecBase.dependencies id
    | "devDependencies" -> DepSpecBase.devDependencies id
    | _ -> $syntaxerror
  }

union:
  a = expr; PLUS; b = expr {
    DepSpecBase.(a + b)
  }

%%


