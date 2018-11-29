// @flow

const path = require('path');
const outdent = require('outdent');
const helpers = require('../test/helpers.js');
const {file, dir, packageJson, createTestSandbox, skipSuiteOnWindows} = helpers;

skipSuiteOnWindows('mixed slashes and backslashes in paths');

describe('Variables available for builds', () => {
  it('provides esy variables via #{..} syntax', async () => {
    const p = await createTestSandbox();
    await p.fixture(
      packageJson({
        name: 'root',
        version: '0.1.0',
        dependencies: {
          dep: '*',
        },
        resolutions: {
          dep: 'link:./dep',
        },
        esy: {
          buildsInSource: true,
          build: [helpers.buildCommand(p, 'hello.js')],
          install: [
            "cp hello.cmd #{self.bin / 'hello.cmd'}",
            "cp hello.js #{self.bin / 'hello.js'}",
          ],
          buildEnv: {
            build_root_id: '#{self.id}',
            build_root_name: '#{self.name}',
            build_root_version: '#{self.version}',
            build_root_root: '#{self.root}',
            build_root_original_root: '#{self.original_root}',
            build_root_target_dir: '#{self.target_dir}',
            build_root_install: '#{self.install}',
            build_root_bin: '#{self.bin}',
            build_root_sbin: '#{self.sbin}',
            build_root_lib: '#{self.lib}',
            build_root_man: '#{self.man}',
            build_root_doc: '#{self.doc}',
            build_root_stublibs: '#{self.stublibs}',
            build_root_toplevel: '#{self.toplevel}',
            build_root_share: '#{self.share}',
            build_root_etc: '#{self.etc}',
          },
          exportedEnv: {
            export_root_id: {val: '#{self.id}'},
            export_root_name: {val: '#{self.name}'},
            export_root_version: {val: '#{self.version}'},
            export_root_root: {val: '#{self.root}'},
            export_root_original_root: {val: '#{self.original_root}'},
            export_root_target_dir: {val: '#{self.target_dir}'},
            export_root_install: {val: '#{self.install}'},
            export_root_bin: {val: '#{self.bin}'},
            export_root_sbin: {val: '#{self.sbin}'},
            export_root_lib: {val: '#{self.lib}'},
            export_root_man: {val: '#{self.man}'},
            export_root_doc: {val: '#{self.doc}'},
            export_root_stublibs: {val: '#{self.stublibs}'},
            export_root_toplevel: {val: '#{self.toplevel}'},
            export_root_share: {val: '#{self.share}'},
            export_root_etc: {val: '#{self.etc}'},
          },
        },
      }),
      file(
        'hello.js',
        outdent`
          let names = [
            "build_root_id",
            "build_root_name",
            "build_root_version",
            "build_root_root",
            "build_root_original_root",
            "build_root_target_dir",
            "build_root_install",
            "build_root_bin",
            "build_root_sbin",
            "build_root_lib",
            "build_root_man",
            "build_root_doc",
            "build_root_stublibs",
            "build_root_toplevel",
            "build_root_share",
            "build_root_etc",
            "build_dep_name",
            "build_dep_version",
            "build_dep_root",
            "build_dep_original_root",
            "build_dep_target_dir",
            "build_dep_install",
            "build_dep_bin",
            "build_dep_sbin",
            "build_dep_lib",
            "build_dep_man",
            "build_dep_doc",
            "build_dep_stublibs",
            "build_dep_toplevel",
            "build_dep_share",
            "build_dep_etc",
            "export_root_id",
            "export_root_name",
            "export_root_version",
            "export_root_root",
            "export_root_original_root",
            "export_root_target_dir",
            "export_root_install",
            "export_root_bin",
            "export_root_sbin",
            "export_root_lib",
            "export_root_man",
            "export_root_doc",
            "export_root_stublibs",
            "export_root_toplevel",
            "export_root_share",
            "export_root_etc",
            "export_dep_name",
            "export_dep_version",
            "export_dep_root",
            "export_dep_original_root",
            "export_dep_target_dir",
            "export_dep_install",
            "export_dep_bin",
            "export_dep_sbin",
            "export_dep_lib",
            "export_dep_man",
            "export_dep_doc",
            "export_dep_stublibs",
            "export_dep_toplevel",
            "export_dep_share",
            "export_dep_etc"
          ]

          names.forEach(name => {
            let value = process.env[name] || '<novalue>';
            console.log(name + "=" + value);
          });
        `,
      ),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '0.2.0',
          esy: {
            buildsInSource: true,
            buildEnv: {
              build_dep_name: '#{self.name}',
              build_dep_version: '#{self.version}',
              build_dep_root: '#{self.root}',
              build_dep_original_root: '#{self.original_root}',
              build_dep_target_dir: '#{self.target_dir}',
              build_dep_install: '#{self.install}',
              build_dep_bin: '#{self.bin}',
              build_dep_sbin: '#{self.sbin}',
              build_dep_lib: '#{self.lib}',
              build_dep_man: '#{self.man}',
              build_dep_doc: '#{self.doc}',
              build_dep_stublibs: '#{self.stublibs}',
              build_dep_toplevel: '#{self.toplevel}',
              build_dep_share: '#{self.share}',
              build_dep_etc: '#{self.etc}',
            },
            exportedEnv: {
              export_dep_id: {val: '#{self.id}', scope: 'global'},
              export_dep_name: {val: '#{self.name}', scope: 'global'},
              export_dep_version: {val: '#{self.version}', scope: 'global'},
              export_dep_root: {val: '#{self.root}', scope: 'global'},
              export_dep_original_root: {val: '#{self.original_root}', scope: 'global'},
              export_dep_target_dir: {val: '#{self.target_dir}', scope: 'global'},
              export_dep_install: {val: '#{self.install}', scope: 'global'},
              export_dep_bin: {val: '#{self.bin}', scope: 'global'},
              export_dep_sbin: {val: '#{self.sbin}', scope: 'global'},
              export_dep_lib: {val: '#{self.lib}', scope: 'global'},
              export_dep_man: {val: '#{self.man}', scope: 'global'},
              export_dep_doc: {val: '#{self.doc}', scope: 'global'},
              export_dep_stublibs: {val: '#{self.stublibs}', scope: 'global'},
              export_dep_toplevel: {val: '#{self.toplevel}', scope: 'global'},
              export_dep_share: {val: '#{self.share}', scope: 'global'},
              export_dep_etc: {val: '#{self.etc}', scope: 'global'},
            },
          },
        }),
      ),
    );
    await p.esy('install');
    await p.esy('build');

    const localStorePath = (...segments) =>
      path.join(p.projectPath, '_esy', 'default', 'store', ...segments);

    const rootId = JSON.parse((await p.esy('build-plan')).stdout).id;
    const depId = JSON.parse((await p.esy('build-plan dep@link:dep')).stdout).id;

    const {stdout} = await p.esy('x hello.cmd');
    expect(stdout.trim()).toEqual(outdent`
build_root_id=<novalue>
build_root_name=<novalue>
build_root_version=<novalue>
build_root_root=<novalue>
build_root_original_root=<novalue>
build_root_target_dir=<novalue>
build_root_install=<novalue>
build_root_bin=<novalue>
build_root_sbin=<novalue>
build_root_lib=<novalue>
build_root_man=<novalue>
build_root_doc=<novalue>
build_root_stublibs=<novalue>
build_root_toplevel=<novalue>
build_root_share=<novalue>
build_root_etc=<novalue>
build_dep_name=<novalue>
build_dep_version=<novalue>
build_dep_root=<novalue>
build_dep_original_root=<novalue>
build_dep_target_dir=<novalue>
build_dep_install=<novalue>
build_dep_bin=<novalue>
build_dep_sbin=<novalue>
build_dep_lib=<novalue>
build_dep_man=<novalue>
build_dep_doc=<novalue>
build_dep_stublibs=<novalue>
build_dep_toplevel=<novalue>
build_dep_share=<novalue>
build_dep_etc=<novalue>
export_root_id=${rootId}
export_root_name=root
export_root_version=0.1.0
export_root_root=${localStorePath('b', rootId)}
export_root_original_root=${p.projectPath}
export_root_target_dir=${localStorePath('b', rootId)}
export_root_install=${localStorePath('i', rootId)}
export_root_bin=${localStorePath('i', rootId, 'bin')}
export_root_sbin=${localStorePath('i', rootId, 'sbin')}
export_root_lib=${localStorePath('i', rootId, 'lib')}
export_root_man=${localStorePath('i', rootId, 'man')}
export_root_doc=${localStorePath('i', rootId, 'doc')}
export_root_stublibs=${localStorePath('i', rootId, 'stublibs')}
export_root_toplevel=${localStorePath('i', rootId, 'toplevel')}
export_root_share=${localStorePath('i', rootId, 'share')}
export_root_etc=${localStorePath('i', rootId, 'etc')}
export_dep_name=dep
export_dep_version=0.2.0
export_dep_root=${localStorePath('b', depId)}
export_dep_original_root=${path.join(p.projectPath, 'dep')}
export_dep_target_dir=${localStorePath('b', depId)}
export_dep_install=${localStorePath('i', depId)}
export_dep_bin=${localStorePath('i', depId, 'bin')}
export_dep_sbin=${localStorePath('i', depId, 'sbin')}
export_dep_lib=${localStorePath('i', depId, 'lib')}
export_dep_man=${localStorePath('i', depId, 'man')}
export_dep_doc=${localStorePath('i', depId, 'doc')}
export_dep_stublibs=${localStorePath('i', depId, 'stublibs')}
export_dep_toplevel=${localStorePath('i', depId, 'toplevel')}
export_dep_share=${localStorePath('i', depId, 'share')}
export_dep_etc=${localStorePath('i', depId, 'etc')}
    `);
  });
});
