/**
 * @flow
 */

import * as path from 'path';
import * as rcUtil from '@esy-ocaml/esy-install/src/util/rc.js';
import {parse} from '@esy-ocaml/esy-install/src/lockfile';

type Rc = {
  'esy-import-path': Array<string>,
};

export function getRcConfigForCwd(cwd: string): Rc {
  return rcUtil.findRc('esy', cwd, (fileText, filePath) => {
    const filePathDir = path.dirname(filePath);
    const {object: values} = parse(fileText, 'yarnrc');

    if (values['esy-import-path'] == null) {
      values['esy-import-path'] = [];
    } else {
      values['esy-import-path'] = values['esy-import-path']
        .split(':')
        .map(p => path.resolve(filePathDir, p));
    }

    return values;
  });
}
