%token <string> ID
%token PLUS
%token LPAREN
%token RPAREN
%token EOF

%left PLUS

%{

%}

%start start
%type <DepSpec.t> start

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
    | "root" -> DepSpec.root
    | "self" -> DepSpec.self
    | _ -> $syntaxerror
  }

package:
  id = ID; {
    match id with
    | "root" -> DepSpec.(package root)
    | "self" -> DepSpec.(package self)
    | _ -> $syntaxerror
  }

select:
  select = ID; LPAREN; id = id; RPAREN {
    match select with
    | "dependencies" -> DepSpec.dependencies id
    | "devDependencies" -> DepSpec.devDependencies id
    | _ -> $syntaxerror
  }

union:
  a = expr; PLUS; b = expr {
    DepSpec.(a + b)
  }

%%


