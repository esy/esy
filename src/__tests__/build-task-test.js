/**
 * @flow
 */

import type {BuildSpec} from '../types';
import {expandWithScope, renderWithScope, fromBuildSpec} from '../build-task';
import * as Config from '../build-config';

function calculate(config, spec, params) {
  const {env, scope} = fromBuildSpec(spec, config, params);
  return {env, scope};
}

function build({name, exportedEnv, dependencies: dependenciesArray}): BuildSpec {
  const dependencies = new Map();
  for (const item of dependenciesArray) {
    dependencies.set(item.id, item);
  }
  return {
    id: name,
    name,
    version: '0.1.0',
    sourcePath: name,
    sourceType: 'immutable',
    dependencies,
    exportedEnv,
    mutatesSourcePath: false,
    shouldBePersisted: true,
    command: null,
    errors: [],
  };
}

const ocaml = build({
  name: 'ocaml',
  exportedEnv: {
    CAML_LD_LIBRARY_PATH: {
      val: '$ocaml__lib/ocaml',
      scope: 'global',
    },
  },
  dependencies: [],
});

const ocamlfind = build({
  name: 'ocamlfind',
  exportedEnv: {
    CAML_LD_LIBRARY_PATH: {
      val: '$ocamlfind__lib/ocaml:$CAML_LD_LIBRARY_PATH',
      scope: 'global',
    },
  },
  dependencies: [ocaml],
});

const lwt = build({
  name: 'lwt',
  exportedEnv: {
    CAML_LD_LIBRARY_PATH: {
      val: '$lwt__lib/ocaml:$CAML_LD_LIBRARY_PATH',
      scope: 'global',
    },
  },
  dependencies: [ocaml],
});

const config = Config.createConfig({
  sandboxPath: '<sandboxPath>',
  storePath: '<storePath>',
  buildPlatform: 'linux',
});

describe('renderWithScope()', function() {
  test('simple replacement: $var syntax', function() {
    const scope = new Map([['name', {value: 'World'}]]);
    expect(renderWithScope('Hello, $name!', scope)).toEqual({
      rendered: 'Hello, World!',
    });
  });

  test('multiple replacements', function() {
    const scope = new Map([['name', {value: 'World'}]]);
    expect(renderWithScope('Hello, $name + $name!', scope)).toEqual({
      rendered: 'Hello, World + World!',
    });
  });

  test('missing in scope', function() {
    const scope = new Map([]);
    expect(renderWithScope('Hello, $unknown!', scope)).toEqual({
      rendered: 'Hello, $unknown!',
    });
  });
});

describe('expandWithScope()', function() {
  test('simple replacement: $var syntax', function() {
    const scope = new Map([['name', {value: 'World'}]]);
    expect(expandWithScope('Hello, $name!', scope)).toEqual({
      rendered: 'Hello, World!',
    });
  });

  test('simple replacement: ${var} syntax', function() {
    const scope = new Map([['name', {value: 'World'}]]);
    expect(expandWithScope('Hello, ${name}!', scope)).toEqual({
      rendered: 'Hello, World!',
    });
  });

  test('multiple replacements', function() {
    const scope = new Map([['name', {value: 'World'}]]);
    expect(expandWithScope('Hello, $name + $name!', scope)).toEqual({
      rendered: 'Hello, World + World!',
    });
  });

  test('missing in scope', function() {
    const scope = new Map([]);
    expect(expandWithScope('Hello, $unknown!', scope)).toEqual({
      rendered: 'Hello, !',
    });
  });

  test('expansion with fallback to default value', function() {
    const scope = new Map([]);
    expect(expandWithScope('Hello, ${unknown:-Me}!', scope)).toEqual({
      rendered: 'Hello, Me!',
    });
  });
});

describe('calculating env', function() {
  // $FlowFixMe: fix jest flow-typed defs
  expect.addSnapshotSerializer({
    test(val) {
      return val.id && val.name && val.dependencies && val.exportedEnv;
    },
    print(val) {
      return `BuildSpec { id: "${val.id}" }`;
    },
  });

  test('build with no exports', function() {
    const app = build({
      name: 'app',
      exportedEnv: {},
      dependencies: [],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('build with local exports', function() {
    const app = build({
      name: 'app',
      exportedEnv: {
        app__var: {val: 'hello'},
      },
      dependencies: [],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('build with global exports', function() {
    const app = build({
      name: 'app',
      exportedEnv: {
        APP: {val: 'hello', scope: 'global'},
      },
      dependencies: [],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('build with global export referencing built-in', function() {
    const app = build({
      name: 'app',
      exportedEnv: {
        APP: {val: 'hello, $app__name', scope: 'global'},
      },
      dependencies: [],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('build with global export referencing built-in (cur-version)', function() {
    const app = build({
      name: 'app',
      exportedEnv: {
        APP: {val: 'hello, $cur__name', scope: 'global'},
      },
      dependencies: [],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('build with (dep with local export)', function() {
    const dep = build({
      name: 'dep',
      exportedEnv: {
        dep__var: {val: 'hello'},
      },
      dependencies: [],
    });
    const app = build({
      name: 'app',
      exportedEnv: {},
      dependencies: [dep],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('build with (dep with local export) with global export referencing dep built-in', function() {
    const dep = build({
      name: 'dep',
      exportedEnv: {},
      dependencies: [],
    });
    const app = build({
      name: 'app',
      exportedEnv: {
        APP: {val: 'hello, $dep__name', scope: 'global'},
      },
      dependencies: [dep],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('build with (dep with local export) with global export referencing dep local export', function() {
    const dep = build({
      name: 'dep',
      exportedEnv: {
        dep__var: {val: 'hello'},
      },
      dependencies: [],
    });
    const app = build({
      name: 'app',
      exportedEnv: {
        APP: {val: '$dep__var, world', scope: 'global'},
      },
      dependencies: [dep],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('build with (dep with local export) with local export referencing dep built-in', function() {
    const dep = build({
      name: 'dep',
      exportedEnv: {},
      dependencies: [],
    });
    const app = build({
      name: 'app',
      exportedEnv: {
        app__var: {val: 'hello, $dep__name'},
      },
      dependencies: [dep],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('build with (dep with local export) with local export referencing dep local export', function() {
    const dep = build({
      name: 'dep',
      exportedEnv: {
        dep__var: {val: 'hello'},
      },
      dependencies: [],
    });
    const app = build({
      name: 'app',
      exportedEnv: {
        app_var: {val: '$dep__var, world'},
      },
      dependencies: [dep],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('build with (dep with (dep with local export) with local export)', function() {
    const depOfDep = build({
      name: 'dep-of-dep',
      exportedEnv: {
        dep_of_dep__var: {val: 'hello'},
      },
      dependencies: [],
    });
    const dep = build({
      name: 'dep',
      exportedEnv: {
        dep__var: {val: 'hello'},
      },
      dependencies: [depOfDep],
    });
    const app = build({
      name: 'app',
      exportedEnv: {},
      dependencies: [dep],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('concatenating global exports', function() {
    const app1 = build({
      name: 'app',
      exportedEnv: {},
      dependencies: [ocamlfind, ocaml],
    });
    expect(calculate(config, app1)).toMatchSnapshot();
    // check that order is deterministic (b/c of topo sort order of deps)
    const app2 = build({
      name: 'app',
      exportedEnv: {},
      dependencies: [ocaml, ocamlfind],
    });
    // TODO: uncomment this and make it pass
    //expect(calculate(config, app1)).toEqual(calculate(config, app2));
  });

  test('concatenating global exports (same level exports)', function() {
    const app = build({
      name: 'app',
      exportedEnv: {},
      dependencies: [ocamlfind, lwt],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('concatenating global exports (same level exports + package itself)', function() {
    const app = build({
      name: 'app',
      exportedEnv: {
        CAML_LD_LIBRARY_PATH: {
          val: '$app__lib:$CAML_LD_LIBRARY_PATH',
          scope: 'global',
        },
      },
      dependencies: [ocamlfind, lwt],
    });
    expect(calculate(config, app)).toMatchSnapshot();
  });

  test('exposing own $cur__bin in $PATH', function() {
    const dep = build({
      name: 'dep',
      exportedEnv: {
        dep__var: {val: 'hello'},
      },
      dependencies: [],
    });
    const app = build({
      name: 'app',
      exportedEnv: {},
      dependencies: [dep],
    });
    const PATH = calculate(config, app, {exposeOwnPath: true}).env.get('PATH');
    expect(PATH).toMatchSnapshot();
  });
});
