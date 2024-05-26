---
id: esy-configuration
title: Configuration
---

esy can be configured through `.esyrc` which esy tries to find in the following
locations (sorted by priority):

1. Sandbox directory: `.esyrc`
2. Home directory: `$HOME/.esyrc`

The following configuration parameters available:

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [`esy-prefix-path`](#esy-prefix-path)
- [`yarn-*`](#yarn-)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

Note that some of them could be also controlled via corresponding environment
variables.

## `esy-prefix-path`

Prefix path controls the location where esy puts its installation caches and
build store. By default it is set to `$HOME/.esy`. To override the default
location put the following lines into `.esyrc`:

```yaml
esy-prefix-path: "/var/lib/esy"
```

If relative path is provided then it will be resolved against the directory
`.esyrc` resides in.

Prefix path could also be set using `$ESY__PREFIX` environment variable.

## `yarn-*`

Any of the yarn configuration parameters can be set in `.esyrc` similar to
`.yarnrc`. See a corresponding [yarn
documentation](https://yarnpkg.com/en/docs/yarnrc) on the matter.

Those parameters will be used by `esy install` and `esy add` commands (which use
yarn under the hood).
