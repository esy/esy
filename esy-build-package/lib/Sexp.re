/**
 * Super simple sexp generation.
 */;

type t =
  | S(string)
  | N(float)
  | I(string)
  | L(list(t));

type item =
  | Value(t)
  | Comment(string);

type doc = list(item);

let render = doc => {
  let buf = Buffer.create(1024);
  let emit = Buffer.add_string(buf);
  let rec emitAtom =
    fun
    | S(v) => {
        emit("\"");
        emit(v);
        emit("\"");
      }
    | N(v) => emit(string_of_float(v))
    | I(v) => emit(v)
    | L(v) => {
        let emitListElement = item => {
          emitAtom(item);
          emit(" ");
        };
        emit("(");
        List.iter(emitListElement, v);
        emit(")");
      };
  let emitItem =
    fun
    | Value(a) => {
        emitAtom(a);
        emit("\n");
      }
    | Comment(comment) => {
        emit("; ");
        emit(comment);
        emit("\n");
      };
  List.iter(emitItem, doc);
  Buffer.contents(buf);
};
