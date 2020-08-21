%token <string> STRING
%token <string> ID
%token QUESTION_MARK
%token COLON
%token DOT
%token SLASH
%token DOLLAR
%token AT
%token AND
%token OR
%token EQ
%token NEQ
%token NOT
%token PAREN_LEFT
%token PAREN_RIGHT
%token EOF

%left QUESTION_MARK
%left OR
%left AND
%left EQ NEQ
%left NOT

%{

  module E = Types.Expr

%}

%start start
%type <Types.Expr.t> start

%%

start:
    e = expr; EOF { e }
  | EOF; { String "" }

expr:
  e = nonempty_list(atom) {
    match e with
    | [e] -> e
    | es -> E.Concat es
  }

(** Expressions which are allowed inside of then branch w/o parens *)
restrictedExpr:
    e = atomString { e }
  | e = atomId { e }
  | e = atomEnv { e }
  | PAREN_LEFT; e = expr; PAREN_RIGHT { e }

atom:
    PAREN_LEFT; e = atom; PAREN_RIGHT { e }
  | e = atomString { e }
  | e = atomId { e }
  | e = atomEnv { e }
  | e = atomCond { e }
  | e = atomAnd { e }
  | e = atomOr { e }
  | e = atomEq { e }
  | e = atomNeq { e }
  | NOT; e = atom { E.Not e }
  | SLASH { E.PathSep }
  | COLON { E.Colon }

atomAnd:
  a = atom; AND; b = atom { E.And (a, b) }

atomOr:
  a = atom; OR; b = atom { E.Or (a, b) }

atomEq:
  a = atom; EQ; b = atom { E.Rel (E.EQ, a, b) }

atomNeq:
  a = atom; NEQ; b = atom { E.Rel (E.NEQ, a, b) }

%inline atomCond:
  cond = atom; QUESTION_MARK; t = restrictedExpr; COLON; e = restrictedExpr { E.Condition (cond, t, e) }

%inline atomString:
  e = STRING { E.String e }

%inline atomEnv:
  DOLLAR; n = ID { E.EnvVar n }

%inline atomId:
  | e = id { E.Var e }

id:
    id = ID { (None, id) }
  | namespace = id_namespace; DOT; id = ID { (Some namespace, id) }


id_namespace:
    n = ID { n }
  | AT; s = ID; SLASH; n = ID { ("@" ^ s ^ "/" ^ n) }

%%

