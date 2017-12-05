/**
 * @flow
 */

import * as CE from '../command-expr.js';

const makeTest = (expr, result) => {
  test(`evaluate: ${expr}`, function() {
    expect(CE.evaluate(expr)).toBe(result);
  });
};

makeTest('Hello, world', 'Hello, world');
makeTest("Hello, #{'world'}", 'Hello, world');
makeTest("#{'Hello'}, world", 'Hello, world');
makeTest("Hello#{', '}world", 'Hello, world');
makeTest("#{'Hello, world'}", 'Hello, world');
makeTest("#{cur.share / 'vim'}", 'ID(cur.share)/vim');
makeTest('#{some-pkg}', 'ID(some-pkg)');
makeTest('#{@opam/merlin}', 'ID(@opam/merlin)');
makeTest('#{cur.bin : $PATH}', 'ID(cur.bin):VAR(PATH)');
makeTest("#{platform '-${VAR}'}", 'ID(platform)-${VAR}');
