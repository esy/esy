%token <string> ID
%token PLUS
%token LPAREN
%token RPAREN
%token EOF

%left PLUS

%{

%}

%start start
%type <Plan.DepSpec.t> start

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
    | "root" -> Plan.DepSpec.root
    | "self" -> Plan.DepSpec.self
    | _ -> $syntaxerror
  }

package:
  id = ID; {
    match id with
    | "root" -> Plan.DepSpec.(package root)
    | "self" -> Plan.DepSpec.(package self)
    | _ -> $syntaxerror
  }

select:
  select = ID; LPAREN; id = id; RPAREN {
    match select with
    | "dependencies" -> Plan.DepSpec.dependencies id
    | "devDependencies" -> Plan.DepSpec.devDependencies id
    | _ -> $syntaxerror
  }

union:
  a = expr; PLUS; b = expr {
    Plan.DepSpec.(a + b)
  }

%%


