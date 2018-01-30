(**
 * A parser of a subset of lockfile syntax enough to parse .esyrc.
 *)

module L = LockfileLexer

type tokens =
  L.t list
  [@@deriving (show, eq)]

type t =
  | Mapping of (string * t) list
  | Number of float
  | String of string
  | Boolean of bool
  [@@deriving (show, eq)]

(* TODO: this should really be lazy but we don't care as we don't expect .esyrc
 * to be large, make it lazy when we are going to use it for large inputs like
 * .esy.lock files.
 *)
let tokensOf v =
  let lexbuf = Lexing.from_string v in
  let rec loop ~acc = function
  | L.EOF -> List.rev (L.EOF::acc)
  | x ->  loop ~acc:(x::acc) (L.read lexbuf)
  in
  loop ~acc:[] (L.read lexbuf)

type parseState =
  | InMapping of { items : (string * t) list }
  | InValue of { key : string; items : (string * t) list }

let parseExn v =
  let tokens = tokensOf v in
  let rec loop state tokens = match state, tokens with
  | InMapping {items}, L.EOF::[] -> Mapping items
  | InMapping {items}, (L.STRING v)::tokens
  | InMapping {items}, (L.IDENTIFIER v)::tokens -> loop (InValue { key = v; items = items }) tokens
  | InMapping _, (L.NEWLINE)::tokens -> loop state tokens
  | InMapping _, (L.EOF::_) -> raise (L.SyntaxError "tokens after EOF")
  | InMapping _, (L.NUMBER _)::_ -> raise (L.SyntaxError "expected newline or string, got number")
  | InMapping _, (L.FALSE)::_ -> raise (L.SyntaxError "expected newline or string, got boolean")
  | InMapping _, (L.TRUE)::_ -> raise (L.SyntaxError "expected newline or string, got boolean")
  | InMapping _, (L.COLON)::_ -> raise (L.SyntaxError "expected newline or string, got colon")
  | InValue _, [] -> raise (L.SyntaxError "expected value, got EOF")
  | InValue _, L.EOF::_ -> raise (L.SyntaxError "expected value, got EOF")
  | InValue _, (L.COLON)::tokens -> loop state tokens
  | InValue _, (L.NEWLINE)::tokens -> loop state tokens
  | InValue {key; items}, (L.NUMBER v)::tokens ->
    let item = (key, Number v) in
    loop (InMapping { items = List.rev (item::items) }) tokens
  | InValue {key; items}, (L.FALSE)::tokens ->
    let item = (key, Boolean false) in
    loop (InMapping { items = List.rev (item::items) }) tokens
  | InValue {key; items}, (L.TRUE)::tokens ->
    let item = (key, Boolean true) in
    loop (InMapping { items = List.rev (item::items) }) tokens
  | InValue {key; items}, (L.STRING v)::tokens
  | InValue {key; items}, (L.IDENTIFIER v)::tokens ->
    let item = (key, String v) in
    loop (InMapping { items = List.rev (item::items) }) tokens
  | _state, (L.COMMA)::_tokens -> raise (L.SyntaxError "syntax is not supported")
  | _, [] -> failwith "token stream does not end with EOF"
  in loop (InMapping { items = [] }) tokens

let parse v =
  try Run.return (parseExn v)
  with L.SyntaxError err -> Run.error err
