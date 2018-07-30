// @flow

const path = require('path');
const fs = require('fs');

const outdent = require('outdent');
const {genFixture, packageJson, symlink, file, dir} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "with-linked-dep-sandbox-env",
    "version": "1.0.0",
    "esy": {
      "build": [
        [
          "bash",
          "-c",
          "echo '#!/bin/bash\necho #{self.name}' > #{self.target_dir / self.name}"
        ],
        "chmod +x $cur__target_dir/$cur__name"
      ],
      "install": ["cp $cur__target_dir/$cur__name $cur__bin/$cur__name"],
      "sandboxEnv": {
        "SANDBOX_ENV_VAR": "global-sandbox-env-var"
      }
    },
    "dependencies": {
      "dep": "*"
    },
    "buildTimeDependencies": {
      "dep2": "*"
    },
    "devDependencies": {
      "dep3": "*"
    }
  }),
  dir('node_modules',
    dir('dep',
      symlink('package.json', path.join('..', '..', 'dep')),
      file('_esylink', './dep')
    ),
    dir('dep2',
      symlink('package.json', path.join('..', '..', 'dep2')),
      file('_esylink', './dep2')
    ),
    dir('dep3',
      symlink('package.json', path.join('..', '..', 'dep3')),
      file('_esylink', './dep3')
    ),
  ),
  dir('dep',
    packageJson({
      "name": "dep",
      "version": "1.0.0",
      "esy": {
        "build": [
          ["sh", "./script.sh", "#{self.target_dir / self.name}"],
          "chmod +x $cur__target_dir/$cur__name"
        ],
        "install": ["cp $cur__target_dir/$cur__name $cur__bin/$cur__name"]
      },
      "dependencies": {}
    }),
    file('script.sh', outdent`
      #!/bin/bash

      echo '#!/bin/bash' >> $1
      echo "echo '$SANDBOX_ENV_VAR-in-dep'" >> $1
    `)
  ),
  dir('dep2',
    packageJson({
      "name": "dep2",
      "version": "1.0.0",
      "esy": {
        "build": [
          ["sh", "./script.sh", "#{self.target_dir / self.name}"],
          "chmod +x $cur__target_dir/$cur__name"
        ],
        "install": ["cp $cur__target_dir/$cur__name $cur__bin/$cur__name"]
      },
      "dependencies": {}
    }),
    file('script.sh', outdent`
      #!/bin/bash

      echo '#!/bin/bash' >> $1
      echo "echo '$SANDBOX_ENV_VAR-in-dep2'" >> $1
    `),
  ),
  dir('dep3',
    packageJson({
      "name": "dep3",
      "version": "1.0.0",
      "license": "MIT",
      "esy": {
        "build": [
          ["sh", "./script.sh", "#{self.target_dir / self.name}"],
          "chmod +x $cur__target_dir/$cur__name"
        ],
        "install": ["cp $cur__target_dir/$cur__name $cur__bin/$cur__name"]
      },
      "dependencies": {}
    }),
    file('script.sh', outdent`
      #!/bin/bash

      echo '#!/bin/bash' >> $1
      echo "echo '$SANDBOX_ENV_VAR-in-dep3'" >> $1
    `)
  ),
];

describe('Build - with linked dep _build', () => {
  let p;

  beforeAll(async () => {
    p = await genFixture(...fixture);
    await p.esy('build');
  });

  it("sandbox env should be visible in runtime dep's all envs", async () => {
    expect.assertions(3);

    const expecting = expect.stringMatching('global-sandbox-env-var-in-dep');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);
  });

  it("sandbox env should not be available in build time dep's envs", async () => {
    expect.assertions(2);

    const expecting = expect.stringMatching('-in-dep2');

    const dep = await p.esy('dep2');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep2');
    expect(b.stdout).toEqual(expecting);
  });

  it("sandbox env should not be available in dev dep's envs", async () => {
    expect.assertions(2);

    const dep = await p.esy('dep3');
    expect(dep.stdout).toEqual(expect.stringMatching('-in-dep3'));

    const {stdout} = await p.esy('x with-linked-dep-sandbox-env');
    expect(stdout).toEqual(expect.stringMatching('with-linked-dep-sandbox-env'));

  });
});
