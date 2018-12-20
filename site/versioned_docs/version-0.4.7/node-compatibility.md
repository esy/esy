---
id: version-0.4.7-node-compatibility
title: Node/npm Compatibility
original_id: node-compatibility
---

esy can install packages from npm registry.

This means `esy install` can also install packages which contain JavaScript
code.

## Accessing installed JS packages

As opposed to a standard way of installing packages into project's
`node_modules` directory esy uses [plug'n'play installation mechanism][yarn-pnp]
(pnp for short) pioneered by [yarn][].

There are few differences though:

- esy puts pnp runtime not as `.pnp.js` but as `_esy/default/pnp.js` (or
  `_esy/NAME/pnp.js` for a named sandbox with name `NAME`).

- To execute pnp enabled `node` one uses `esy node` invocation.

All binaries installed with npm packages are accessible via `esy COMMAND`
invocation, few example:

- To run webpack (comes from `webpack-cli`):
  ```bash
  % esy webpack
  ```

- To run `flow` (comes from `flow-bin` package):
  ```bash
  % esy flow
  ```

## Caveats

- Not all npm packages currently support being installed with plug'n'play
  installation mechanism.

- Not all npm lifecycle hooks are supported right now (only `install` and
  `postinstall` are being run).

[yarn-pnp]: https://github.com/arcanis/rfcs/blob/6fc13d52f43eff45b7b46b707f3115cc63d0ea5f/accepted/0000-plug-an-play.md
[yarn]: https://github.com/yarnpkg/yarn
