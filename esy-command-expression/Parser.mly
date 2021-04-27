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

%start start
%type <Types.Expr.t> start

%{

  open Types.Expr

%}

%%

start:
   e = expr; EOF { e }
  | EOF; { String "" }

expr:
  e = nonempty_list(atom) {
    match e with
    | [e] -> e
    | es -> Concat es
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
  | NOT; e = atom { Not e }
  | SLASH { PathSep }
  | COLON { Colon }

atomAnd:
  a = atom; AND; b = atom { And (a, b) }

atomOr:
  a = atom; OR; b = atom { Or (a, b) }

atomEq:
  a = atom; EQ; b = atom { Rel (EQ, a, b) }

atomNeq:
  a = atom; NEQ; b = atom { Rel (NEQ, a, b) }

%inline atomCond:
  cond = atom; QUESTION_MARK; t = restrictedExpr; COLON; e = restrictedExpr { Condition (cond, t, e) }

%inline atomString:
  e = STRING { String e }

%inline atomEnv:
  DOLLAR; n = ID { EnvVar n }

%inline atomId:
  | e = id { Var e }

id:
    id = ID { (None, id) }
  | namespace = id_namespace; DOT; id = ID { (Some namespace, id) }


id_namespace:
    n = ID { n }
  | AT; s = ID; SLASH; n = ID { ("@" ^ s ^ "/" ^ n) }

%%

