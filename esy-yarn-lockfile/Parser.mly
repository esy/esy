%token <float> NUMBER
%token <string> IDENTIFIER
%token TRUE
%token FALSE
%token <string> STRING
%token COLON
%token INDENT
%token DEDENT
%token <int> NEWLINE
%token EOF

%{

  open Types

%}

%start start
%type <Types.t> start

%%

start:
  v = mapping; EOF { v }
  | EOF { Mapping [] }

value:
    v = scalar { Scalar v }
  | INDENT; v = mapping; DEDENT { v }
  | INDENT; v = seq; DEDENT { v }
  | INDENT; DEDENT { Types.Mapping [] }

scalar:
    TRUE { Boolean true }
  | FALSE { Boolean false }
  | s = STRING { String s }
  | s = IDENTIFIER { String s }
  | n = NUMBER { Number n }

mapping:
  items = separated_nonempty_list(NEWLINE, item) { Types.Mapping items }

item:
  key = key; COLON; value = value; { (key, value) }

key:
  s = IDENTIFIER { s }
  | s = STRING { s }

seq:
  items = separated_nonempty_list(NEWLINE, scalar) { Types.Sequence items }
