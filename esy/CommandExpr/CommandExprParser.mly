%token <string> STRING
%token <string> ID
%token QUESTION_MARK
%token COLON
%token DOT
%token SLASH
%token DOLLAR
%token AT
%token AND
%token PAREN_LEFT
%token PAREN_RIGHT
%token EOF

%left QUESTION_MARK
%left AND

%{

  module E = CommandExprTypes.Expr

%}

%start start
%type <CommandExprTypes.Expr.t> start

%%

start:
  e = expr; EOF { e }

expr:
  | e = exprList { e }
  | PAREN_LEFT; e = exprList; PAREN_RIGHT { e }

(** Expressions which are allowed inside of then branch w/o parens *)
restrictedExpr:
    e = atomString { e }
  | e = atomId { e }
  | e = atomEnv { e }
  | PAREN_LEFT; e = expr; PAREN_RIGHT { e }

exprList:
  e = nonempty_list(atom) {
    match e with
    | [e] -> e
    | es -> E.Concat es
  }

atom:
    PAREN_LEFT; e = atom; PAREN_RIGHT { e }
  | e = atomString { e }
  | e = atomId { e }
  | e = atomEnv { e }
  | e = atomCond { e }
  | e = atomAnd { e }
  | SLASH { E.PathSep }
  | COLON { E.Colon }

atomAnd:
  a = atom; AND; b = atom { E.And (a, b) }

%inline atomCond:
  cond = atom; QUESTION_MARK; t = restrictedExpr; COLON; e = restrictedExpr { E.Condition (cond, t, e) }

%inline atomString:
  e = STRING { E.String e }

%inline atomEnv:
  DOLLAR; n = ID { E.EnvVar n }

%inline atomId:
  | e = id { E.Var e }

id:
    n = id_segment { [n] }
  | n = id_segment; DOT; ns = id { (n::ns) }

id_segment:
    n = ID { n }
  | AT; s = ID; SLASH; n = ID { ("@" ^ s ^ "/" ^ n) }

%%

