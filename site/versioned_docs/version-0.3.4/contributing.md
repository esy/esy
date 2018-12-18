---
id: version-0.3.4-contributing
title: Contributing
original_id: contributing
---


## Editor Integration For New Editor:

Currently supported editor integrations:

| LSP                                                           | Vim                                              | Emacs             |
|---------------------------------------------------------------|--------------------------------------------------|-------------------|
| [DONE](https://github.com/freebroccolo/ocaml-language-server) | [DONE](https://github.com/jordwalke/vim-reason)  | HELP APPRECIATED  |

* Note: The Vim plugin does not yet have support for `.ml` file extensions and
currently only activates upon `.re`.
* Note: For VSCode, editing multiple projects simultaneously requires a separate
window per project.


When you edit an `esy` project in editors with supported integration,
the dev environment will be correctly constructed so that
all your dependencies are seen by the editor, while maintaining isolation
between multiple projects.

That means your autocomplete "Just Works" according to what is listed in your
`esy.json`/`package.json`, and you can edit multiple projects simultaneously
even when each of these projects have very different versions of dependencies
(including compiler versions).


[hello-reason](https://github.com/esy-ocaml/hello-reason) is an example project
that uses `esy` to manage dependencies and works well with either of those
editor plugins mentioned. Simply clone that project, `esy`, and then open a `.re` file in any of the supported editors/plugins
mentioned.

### Helping Out With Editor Integration

Help with the Emacs plugin is appreciated, and if contributing supobprt it is encouraged
that you model the plugin implementation after the `vim-reason` plugin.
At a high level here is what editor support should do:

- For each buffer/file opened, determine which `esy` project it belongs to, if any.
- For each project, determine the "phase".
  - The phase is either, `'no-esy-field'`, `'uninitialized', `'installed'`, or `'built'`.
- Provide some commands such as
- Implement some commands such as:
  - `EsyFetchProjectInfo`: Show the project's `package.json`, and the "stage" of
    the project. 
  - `Reset`: Reset any caches, and internal knowledge of buffers/projects.
  - `EsyExec`: Execute a command in the current buffer's project environment.
  - `EsyBuilds`: Run the `esy ls-builds` command.
  - `EsyLibs`: Run the `esy ls-libs` command.
  - `EsyModules`: Run the `esy ls-modules` command.
- As soon as the phase is finally in the `built` state, initialize a merlin process
  upon the first `.re`/`.ml` file opened. That should use the `EsyExec` functionality
  to ensure the process is being started within the correct environment per project.

See the implementation of `vim-reason` [here](https://github.com/jordwalke/vim-reason/blob/master/autoload/esy.vim)
