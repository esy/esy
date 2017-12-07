/**
 * @flow
 */

import * as CE from '../command-expr.js';

const makeTest = (expr, result) => {
  test(`evaluate: ${expr}`, function() {
    expect(CE.evaluate(expr)).toBe(result);
  });
};

const makeTestExpectToFail = expr => {
  test(`evaluate: ${expr}`, function() {
    expect(() => CE.evaluate(expr)).toThrow();
  });
};

makeTest('Hello, world', 'Hello, world');
makeTest("Hello, #{'world'}", 'Hello, world');
makeTest("#{'Hello'}, world", 'Hello, world');
makeTest("Hello#{', '}world", 'Hello, world');
makeTest("#{'Hello, world'}", 'Hello, world');
makeTest("#{cur.share / 'vim'}", 'ID(cur.share) PATH_SEP vim');
makeTest('#{some-pkg}', 'ID(some-pkg)');
makeTest('#{@opam/merlin}', 'ID(@opam/merlin)');
makeTest('#{@opam/merlin.bin}', 'ID(@opam/merlin.bin)');
makeTest('#{pkg__dot__js.bin}', 'ID(pkg.js.bin)');
makeTest('#{@opam/pkg__dot__js.bin}', 'ID(@opam/pkg.js.bin)');
makeTest('#{cur.bin : $PATH}', 'ID(cur.bin) COLON VAR(PATH)');
makeTest("#{platform '-${VAR}'}", 'ID(platform)-${VAR}');

makeTestExpectToFail('Hello #{');
makeTestExpectToFail('Hello ${');
makeTestExpectToFail("Hello #{'}");
makeTestExpectToFail('Hello #{$}');
makeTestExpectToFail('Hello #{sd.asda.^}');
