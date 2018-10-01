// @flow

const outdent = require('outdent');
const helpers = require('./test/helpers.js');
const {isWindows, packageJson, dir, file, createTestSandbox} = helpers;

const path = require('path');
const fsUtils = require('./test/fs');

type Dir = {
  type: 'dir',
  basename: string,
  nodes: Node[],
};

type File = {
  type: 'file',
  basename: string,
  perm: number,
  data: string,
};

type Node = Dir | File;

const umask = process.umask();
// seems like in Windows we always get 0o666
const perm755 = !isWindows ? 0o777 - umask : 0o666;
const perm644 = !isWindows ? 0o666 - umask : 0o666;

async function crawl(p: string): Promise<?Node> {
  if (!(await fsUtils.exists(p))) {
    return null;
  }

  const stat = await fsUtils.stat(p);
  if (stat.isDirectory()) {
    const items = await fsUtils.readdir(p);
    const nodes = await Promise.all(items.map(name => crawl(path.join(p, name))));
    nodes.sort(function compareNode(a, b) {
      if (a.basename > b.basename) {
        return 1;
      } else if (a.basename < b.basename) {
        return -1;
      } else {
        return 0;
      }
    });
    return {
      type: 'dir',
      nodes,
      basename: path.basename(p),
    };
  } else if (stat.isFile()) {
    const data = await fsUtils.readFile(p, 'utf8');
    return {
      type: 'file',
      data,
      perm: stat.mode & 0o777,
      basename: path.basename(p),
    };
  } else {
    throw new Error(`unknown file at ${p}`);
  }
}

describe('esy-installer', () => {
  async function getInstallDir(p) {
    const iStore = path.join(p.projectPath, '_esy', 'default', 'store', 'i');
    const items = await fsUtils.readdir(iStore);
    if (items.length !== 1) {
      throw new Error('expected single directory inside store/i');
    }
    return path.join(iStore, items[0]);
  }

  it('installs according to spec', async () => {
    // see https://opam.ocaml.org/doc/2.0/Manual.html#lt-pkgname-gt-install
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {
          build: 'true',
        },
      }),
      file(
        'root.install',
        outdent`
          lib: [
            "lib/hello-lib"
          ]
          lib_root: [
            "lib/hello-lib-root"
          ]
          libexec: [
            "lib/hello-libexec"
          ]
          libexec_root: [
            "lib/hello-libexec-root"
          ]
          bin: [
            "bin/hello-bin"
            "bin/install-with-a-different-name-please" {"simple"}
          ]
          sbin: [
            "bin/hello-sbin"
          ]
          toplevel: [
            "hello-toplevel"
          ]
          share: [
            "share/hello-share"
          ]
          share_root: [
            "share/hello-share-root"
          ]
          etc: [
            "hello-etc"
          ]
          doc: [
            "hello-doc"
          ]
          stublibs: [
            "lib/hello-stub"
          ]
          man: [
            "doc/hello.1"
            "doc/hello.2" {"man2/hello.2"}
          ]
        `,
      ),
      dir(
        'bin',
        file('hello-bin', 'hello-bin'),
        file('hello-sbin', 'hello-sbin'),
        file('install-with-a-different-name-please', 'simple'),
      ),
      dir(
        'lib',
        file('hello-stub', 'hello-stub'),
        file('hello-lib', 'hello-lib'),
        file('hello-lib-root', 'hello-lib-root'),
        file('hello-libexec', 'hello-libexec'),
        file('hello-libexec-root', 'hello-libexec-root'),
      ),
      dir('doc', file('hello.1', 'hello.1'), file('hello.2', 'hello.2')),
      file('hello-toplevel', 'hello-toplevel'),
      dir(
        'share',
        file('hello-share', 'hello-share'),
        file('hello-share-root', 'hello-share-root'),
      ),
      file('hello-etc', 'hello-etc'),
      file('hello-doc', 'hello-doc'),
    ];
    const p = await createTestSandbox(...fixture);
    await p.esy('x ls');
    const installDir = await getInstallDir(p);
    const node = await crawl(installDir);

    const man = {
      type: 'dir',
      basename: 'man',
      nodes: [
        {
          type: 'dir',
          basename: 'man1',
          nodes: [
            {
              type: 'file',
              basename: 'hello.1',
              data: 'hello.1',
              perm: perm644,
            },
          ],
        },
        {
          type: 'dir',
          basename: 'man2',
          nodes: [
            {
              type: 'file',
              basename: 'hello.2',
              data: 'hello.2',
              perm: perm644,
            },
          ],
        },
      ],
    };

    const share = {
      type: 'dir',
      basename: 'share',
      nodes: [
        {
          type: 'file',
          basename: 'hello-share-root',
          data: 'hello-share-root',
          perm: perm644,
        },
        {
          type: 'dir',
          basename: 'root',
          nodes: [
            {
              type: 'file',
              basename: 'hello-share',
              data: 'hello-share',
              perm: perm644,
            },
          ],
        },
      ],
    };

    const lib = {
      type: 'dir',
      basename: 'lib',
      nodes: [
        {
          type: 'file',
          basename: 'hello-lib-root',
          data: 'hello-lib-root',
          perm: perm644,
        },
        {
          type: 'file',
          basename: 'hello-libexec-root',
          data: 'hello-libexec-root',
          perm: perm755,
        },
        {
          type: 'dir',
          basename: 'root',
          nodes: [
            {
              type: 'file',
              basename: 'hello-lib',
              data: 'hello-lib',
              perm: perm644,
            },
            {
              type: 'file',
              basename: 'hello-libexec',
              data: 'hello-libexec',
              perm: perm755,
            },
          ],
        },
        {
          type: 'dir',
          basename: 'stublibs',
          nodes: [
            {
              type: 'file',
              basename: 'hello-stub',
              data: 'hello-stub',
              perm: perm755,
            },
          ],
        },
        {
          type: 'dir',
          basename: 'toplevel',
          nodes: [
            {
              type: 'file',
              basename: 'hello-toplevel',
              data: 'hello-toplevel',
              perm: perm644,
            },
          ],
        },
      ],
    };

    const etc = {
      type: 'dir',
      basename: 'etc',
      nodes: [
        {
          type: 'dir',
          basename: 'root',
          nodes: [
            {
              type: 'file',
              basename: 'hello-etc',
              data: 'hello-etc',
              perm: perm644,
            },
          ],
        },
      ],
    };

    const doc = {
      type: 'dir',
      basename: 'doc',
      nodes: [
        {
          type: 'dir',
          basename: 'root',
          nodes: [
            {
              type: 'file',
              basename: 'hello-doc',
              data: 'hello-doc',
              perm: perm644,
            },
          ],
        },
      ],
    };

    const bin = {
      basename: 'bin',
      type: 'dir',
      nodes: [
        {
          type: 'file',
          basename: 'hello-bin',
          data: 'hello-bin',
          perm: perm755,
        },
        {
          type: 'file',
          basename: 'simple',
          data: 'simple',
          perm: perm755,
        },
      ],
    };

    const sbin = {
      type: 'dir',
      basename: 'sbin',
      nodes: [
        {
          type: 'file',
          basename: 'hello-sbin',
          data: 'hello-sbin',
          perm: perm755,
        },
      ],
    };

    const toplevel = {
      type: 'dir',
      basename: 'toplevel',
      nodes: [],
    };

    expect(node).toMatchObject({
      type: 'dir',
      nodes: [
        {type: 'dir', nodes: [{type: 'file', basename: 'storePrefix'}], basename: '_esy'},
        bin,
        doc,
        etc,
        lib,
        man,
        sbin,
        share,
        toplevel,
      ],
    });
  });

  it('can be invoked via esy-installer command', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {
          build: 'true',
          install: 'esy-installer root.install',
        },
      }),
      file(
        'root.install',
        outdent`
          bin: [
            "bin/hello-bin"
          ]
        `,
      ),
      file(
        'ignored.install',
        outdent`
          bin: [
            "bin/hello-oops"
          ]
        `,
      ),
      dir('bin', file('hello-oops', 'hello-oops'), file('hello-bin', 'hello-bin')),
    ];
    const p = await createTestSandbox(...fixture);
    await p.esy('x ls');
    expect(await crawl(path.join(await getInstallDir(p), 'bin'))).toMatchObject({
      type: 'dir',
      basename: 'bin',
      nodes: [
        {
          type: 'file',
          basename: 'hello-bin',
          data: 'hello-bin',
          perm: perm755,
        },
      ],
    });
  });

  it('can be invoked via esy-installer command (via path)', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {
          build: 'true',
          install: 'esy-installer ./root.install',
        },
      }),
      file(
        'root.install',
        outdent`
          bin: [
            "bin/hello-bin"
          ]
        `,
      ),
      dir('bin', file('hello-bin', 'hello-bin')),
    ];
    const p = await createTestSandbox(...fixture);
    await p.esy('x ls');
    expect(await crawl(path.join(await getInstallDir(p), 'bin'))).toMatchObject({
      type: 'dir',
      basename: 'bin',
      nodes: [
        {
          type: 'file',
          basename: 'hello-bin',
          data: 'hello-bin',
          perm: perm755,
        },
      ],
    });
  });

  it('can be invoked via esy-installer command (multiple invocations)', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {
          build: 'true',
          install: ['esy-installer ./root.install', 'esy-installer ./other.install'],
        },
      }),
      file(
        'root.install',
        outdent`
          bin: [
            "bin/hello-bin"
          ]
        `,
      ),
      file(
        'other.install',
        outdent`
          bin: [
            "bin/hello-bin2"
          ]
        `,
      ),
      dir('bin', file('hello-bin', 'hello-bin'), file('hello-bin2', 'hello-bin2')),
    ];
    const p = await createTestSandbox(...fixture);
    await p.esy('x ls');
    expect(await crawl(path.join(await getInstallDir(p), 'bin'))).toMatchObject({
      type: 'dir',
      basename: 'bin',
      nodes: [
        {
          type: 'file',
          basename: 'hello-bin',
          data: 'hello-bin',
          perm: perm755,
        },
        {
          type: 'file',
          basename: 'hello-bin2',
          data: 'hello-bin2',
          perm: perm755,
        },
      ],
    });
  });

  it('adds .exe extension on win32', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {
          build: 'true',
        },
      }),
      file(
        'root.install',
        outdent`
          bin: [
            "bin/hello-bin"
          ]
        `,
      ),
      dir('bin', file('hello-bin.exe', 'hello-bin.exe')),
    ];
    const p = await createTestSandbox(...fixture);
    await p.esy('x ls', {env: {ESY_INSTALLER__FORCE_EXE: 'true'}});
    expect(await crawl(path.join(await getInstallDir(p), 'bin'))).toMatchObject({
      type: 'dir',
      basename: 'bin',
      nodes: [
        {
          type: 'file',
          basename: 'hello-bin.exe',
          data: 'hello-bin.exe',
          perm: perm755,
        },
      ],
    });
  });

  it('skips non-existent file marked with leading ?', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {
          build: 'true',
        },
      }),
      file(
        'root.install',
        outdent`
          bin: [
            "bin/hello-bin"
            "?bin/exists" {"ok"}
            "?bin/exists"
            "?bin/does-not-exist"
          ]
        `,
      ),
      dir('bin', file('exists', 'exists'), file('hello-bin', 'hello-bin')),
    ];
    const p = await createTestSandbox(...fixture);
    await p.esy('x ls');
    expect(await crawl(path.join(await getInstallDir(p), 'bin'))).toMatchObject({
      type: 'dir',
      basename: 'bin',
      nodes: [
        {
          type: 'file',
          basename: 'exists',
          data: 'exists',
          perm: perm755,
        },
        {
          type: 'file',
          basename: 'hello-bin',
          data: 'hello-bin',
          perm: perm755,
        },
        {
          type: 'file',
          basename: 'ok',
          data: 'exists',
          perm: perm755,
        },
      ],
    });
  });
});
