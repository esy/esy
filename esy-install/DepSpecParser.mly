%token <string> ID
%token PLUS
%token LPAREN
%token RPAREN
%token EOF

%left PLUS

%{

%}

%start start
%type <Solution.DepSpec.t> start

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
    | "root" -> Solution.DepSpec.root
    | "self" -> Solution.DepSpec.self
    | _ -> $syntaxerror
  }

package:
  id = ID; {
    match id with
    | "root" -> Solution.DepSpec.(package root)
    | "self" -> Solution.DepSpec.(package self)
    | _ -> $syntaxerror
  }

select:
  select = ID; LPAREN; id = id; RPAREN {
    match select with
    | "dependencies" -> Solution.DepSpec.dependencies id
    | "devDependencies" -> Solution.DepSpec.devDependencies id
    | _ -> $syntaxerror
  }

union:
  a = expr; PLUS; b = expr {
    Solution.DepSpec.(a + b)
  }

%%


