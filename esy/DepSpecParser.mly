%token <string> ID
%token PLUS
%token LPAREN
%token RPAREN
%token EOF

%left PLUS

%{

%}

%start start
%type <BuildSandbox.DepSpec.t> start

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
    | "root" -> BuildSandbox.DepSpec.root
    | "self" -> BuildSandbox.DepSpec.self
    | _ -> $syntaxerror
  }

package:
  id = ID; {
    match id with
    | "root" -> BuildSandbox.DepSpec.(package root)
    | "self" -> BuildSandbox.DepSpec.(package self)
    | _ -> $syntaxerror
  }

select:
  select = ID; LPAREN; id = id; RPAREN {
    match select with
    | "dependencies" -> BuildSandbox.DepSpec.dependencies id
    | "devDependencies" -> BuildSandbox.DepSpec.devDependencies id
    | _ -> $syntaxerror
  }

union:
  a = expr; PLUS; b = expr {
    BuildSandbox.DepSpec.(a + b)
  }

%%


