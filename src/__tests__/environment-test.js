/**
 * @flow
 */

import type {BuildSpec} from '../types';
import {createConfig} from '../build-config';
import {fromBuildSpec} from '../build-task';
import {printEnvironment} from '../environment';

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
    dependencies,
    exportedEnv,
    mutatesSourcePath: false,
    shouldBePersisted: true,
    command: null,
    errors: [],
  };
}

const config = createConfig({
  sandboxPath: '<sandboxPath>',
  storePath: '<storePath>',
});

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

describe('printEnvironment()', function() {
  test('printing environment', function() {
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
    const {env} = fromBuildSpec(app, config);
    expect(printEnvironment(env)).toMatchSnapshot();
  });
});
