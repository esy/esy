%token <string> ID
%token PLUS
%token LPAREN
%token RPAREN
%token EOF

%left PLUS

%{

%}

%start start
%type <FetchDepSpec.t> start

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
    | "root" -> FetchDepSpec.root
    | "self" -> FetchDepSpec.self
    | _ -> $syntaxerror
  }

package:
  id = ID; {
    match id with
    | "root" -> FetchDepSpec.(package root)
    | "self" -> FetchDepSpec.(package self)
    | _ -> $syntaxerror
  }

select:
  select = ID; LPAREN; id = id; RPAREN {
    match select with
    | "dependencies" -> FetchDepSpec.dependencies id
    | "devDependencies" -> FetchDepSpec.devDependencies id
    | _ -> $syntaxerror
  }

union:
  a = expr; PLUS; b = expr {
    FetchDepSpec.(a + b)
  }

%%


