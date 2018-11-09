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

%}

%start start
%type <Types.t> start

%%

start:
  v = mapping; EOF { v }
  | EOF { Types.Mapping [] }

value:
    TRUE { Types.Boolean true }
  | FALSE { Types.Boolean false }
  | s = STRING { Types.String s }
  | s = IDENTIFIER { Types.String s }
  | n = NUMBER { Types.Number n }
  | INDENT; v = mapping; DEDENT { v }
  | INDENT; v = seq; DEDENT { v }
  | INDENT; DEDENT { Types.Mapping [] }

mapping:
  items = separated_nonempty_list(NEWLINE, item) { Types.Mapping items }

item:
  key = key; COLON; value = value; { (key, value) }

key:
  s = IDENTIFIER { s }
  | s = STRING { s }

seq:
  items = separated_nonempty_list(NEWLINE, value) { Types.Sequence items }
