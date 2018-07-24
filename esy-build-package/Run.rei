/*

	A little DSL to script commands.

 */

type err('b) =
  [> | `Msg(string) | `CommandError(Cmd.t, Bos.OS.Cmd.status)] as 'b;

type t('v, 'e) = result('v, err('e));

let ok : t(unit, _);
let return : 'v => t('v, _);

let rm : EsyLib.Path.t => t(unit, _);
let rmdir : EsyLib.Path.t => t(unit, _);
let mv : (~force: bool=?, EsyLib.Path.t, EsyLib.Path.t) => t(unit, _);
let mkdir : EsyLib.Path.t => t(unit, _);
let realpath : EsyLib.Path.t => t(EsyLib.Path.t, _);
let exists : EsyLib.Path.t => t(bool, _);
let withCwd : (EsyLib.Path.t, ~f: unit => t('a, 'e)) => t('a, 'e);
let symlink : (~force: bool=?, ~target: EsyLib.Path.t, EsyLib.Path.t) => t(unit, _);
let symlinkTarget : EsyLib.Path.t => t(EsyLib.Path.t, _);
let putTempFile : string => result(EsyLib.Path.t, [> Rresult.R.msg ]);

let coerceFrmMsgOnly : result('a, [ `Msg(string) ]) => t('a, _);

let v : string => EsyLib.Path.t;
let (/) : EsyLib.Path.t => string => EsyLib.Path.t;

let traverse : (
    EsyLib.Path.t,
    (EsyLib.Path.t, Unix.stats) => t(unit, 'e)
  ) => t(unit, 'e)

module Let_syntax: {
  let bind: (~f: 'v1 => t('v2, 'err), t('v1, 'err)) => t('v2, 'err);
}
