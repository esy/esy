/**
 * Super simple sexp generation.
 */;

type t = list(item)
and item =
  | Value(value)
  | Comment(string)
and value =
  | S(string)
  | N(float)
  | NI(int)
  | I(string)
  | L(list(value));

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
    | NI(v) => emit(string_of_int(v))
    | I(v) => emit(v)
    | L(v) => {
        let f = item => {
          emitAtom(item);
          emit(" ");
        };
        emit("(");
        List.iter(~f, v);
        emit(")");
      };
  let f =
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
  List.iter(~f, doc);
  Buffer.contents(buf);
};
