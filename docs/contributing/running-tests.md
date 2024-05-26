---
id: running-tests
title: Running Tests
---

`esy` has primarily 3 kinds of tests.

1. Unit tests - useful when developing parsers etc
2. Slow end-to-end tests 
3. Fast end-to-end tests


## Unit Tests

These are present inline in the `*.re` files. To run them,

```
esy b dune runtest
```

## Fast end-to-end tests

These are present in `test-e2e` folder and are written in JS. They're run by `jest`

```
yarn jest
```

## Slow end-to-end tests
They're present in `test-e2e-slow` and are written in JS. They're supposed to mimick the user's workflow
as closely as possible.

By placing `@slowtest` token in commit messages, we mark the commit ready for the slow tests framework
(tests that hit the network). They are run with `node test-e2e-slow/run-slow-tests.js`

## Windows

In cases e2e tests fail with `Host key verification failed.`, you might have to create ssh keys
in the cygwin shall and add them to your github profile.

1. Enter cygwin installed by esy (not the global one)

```sh
.\node_modules\esy-bash\re\_build\default\bin\EsyBash.exe bash
```

2. Generate ssh keys

```sh
ssh-keygen
```

3. Add the public key to you Github profile

4. Add the following to the bash rc of the cygwin instance

```sh
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_rsa
```

## Troubleshooting

While running `yarn jest`, snapshots can get outdated as new commits are made. You might see the following multiple times:

```txt
 ● <test suite> errors › test name

expect(received).toEqual(expected) // deep equality
- Expected  - 1
+ Received  + 1
@@ -1,6 +1,6 @@
- info install 0.7.2-124-g290c33aa (using package.json)
+ info install 0.7.2-115-g20692a3a (using package.json) 
```

Run,

```sh
sh ./esy-version/version.sh --reason > ./esy-version/EsyVersion.re
esy
```
And then, run the tests again with `yarn jest` as usual.
