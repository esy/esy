/**
 * @flow
 */

import * as path from 'path';
import * as rcUtil from '@esy-ocaml/esy-install/src/util/rc.js';
import {parse} from '@esy-ocaml/esy-install/src/lockfile';

type Rc = {
  'esy-import-path': Array<string>,
  'esy-prefix-path': ?string,
};

export function getRcConfigForCwd(cwd: string): Rc {
  return rcUtil.findRc('esy', cwd, (fileText, filePath) => {
    const filePathDir = path.dirname(filePath);
    const {object: values} = parse(fileText, 'esyrc');

    function coerceToPath(key, fallback = null) {
      const v = values[key];
      if (v != null) {
        values[key] = path.resolve(filePathDir, v);
      } else {
        values[key] = fallback;
      }
    }

    function coerceToPathList(key, fallback = []) {
      const v = values[key];
      if (v != null) {
        values[key] = v.split(':').map(v => path.resolve(filePathDir, v));
      } else {
        values[key] = fallback;
      }
    }

    coerceToPathList('esy-import-path');
    coerceToPath('esy-prefix-path');

    return values;
  });
}
