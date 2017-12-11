/**
 * @flow
 */

import type {
  Sandbox,
  BuildSpec,
  Config,
  BuildTask,
  Environment,
  EnvironmentBinding,
  BuildScope,
  BuildPlatform,
} from './types';

import outdent from 'outdent';
import {quoteArgIfNeeded} from './lib/shell';
import * as errors from './errors.js';
import * as path from './lib/path';
import * as Map from './lib/Map.js';
import * as lang from './lib/lang.js';
import * as Graph from './graph';
import * as Env from './environment';
import * as CommandExpr from './command-expr.js';

type FromSandboxParams = {
  env?: Environment,
  includeDevDependencies?: true,
};

export function fromSandbox<Path: path.Path>(
  sandbox: Sandbox,
  config: Config<Path>,
  params?: FromSandboxParams = {},
): BuildTask {
  const env = [];
  if (sandbox.env) {
    env.push(...sandbox.env);
  }
  if (params.env != null) {
    env.push(...params.env);
  }
  let spec = sandbox.root;
  if (params.includeDevDependencies) {
    spec = ({...spec, dependencies: new Map.Map(spec.dependencies)}: any);
    for (const devDep of sandbox.devDependencies.values()) {
      spec.dependencies.set(devDep.id, devDep);
    }
  }
  return fromBuildSpec(spec, config, {env});
}

type FromBuildSpecParams = {
  env?: Environment,
};

type ExportedEnv = {
  env: Environment,
  globalEnv: Environment,
};

type FoldState = {
  task: BuildTask,
} & ExportedEnv;

type EnvironmentInProgress = {
  env: Environment,
  index: Map.Map<string, EnvironmentBinding>,
};

/**
 * Produce a task graph from a build spec graph.
 */
export function fromBuildSpec(
  rootSpec: BuildSpec,
  config: Config<path.Path>,
  params?: FromBuildSpecParams = {},
): BuildTask {
  const {task} = Graph.topologicalFold(rootSpec, createTask);

  function createTask(
    dependencies: Map.Map<string, FoldState>,
    allDependencies: Map.Map<string, FoldState>,
    spec: BuildSpec,
  ): {task: BuildTask, env: Environment, globalEnv: Environment} {
    const scopes = getExportedEnv(config, dependencies, allDependencies, spec);

    const OCAMLPATH = [];
    const PATH = [];
    const MAN_PATH = [];

    const reversedAllDependencies = Array.from(allDependencies.values());
    reversedAllDependencies.reverse();
    for (const dep of reversedAllDependencies) {
      OCAMLPATH.push(config.getFinalInstallPath(dep.task.spec, 'lib'));
      PATH.push(config.getFinalInstallPath(dep.task.spec, 'bin'));
      MAN_PATH.push(config.getFinalInstallPath(dep.task.spec, 'man'));
    }

    // In ideal world we wouldn't need it as the whole toolchain should be
    // sandboxed. This isn't the case unfortunately.
    PATH.push('$PATH');
    MAN_PATH.push('$MAN_PATH');

    const env: EnvironmentInProgress = {env: [], index: Map.create()};

    function addToEnv(env, bindings) {
      for (const binding of bindings) {
        const prevBinding = env.index.get(binding.name);
        if (prevBinding != null) {
          if (prevBinding.builtIn) {
            const reason = 'Attempts to override a built-in variable of the same name';
            if (binding.origin != null) {
              throw new BuildEnvExportError(binding.origin, binding, reason);
            } else {
              throw new EnvError(binding, reason);
            }
          }
          if (prevBinding.exclusive) {
            const reason =
              'Attempts to override an environment variable which was marked as exclusive';
            if (binding.origin != null) {
              throw new BuildEnvConflictError(
                binding.origin,
                binding,
                prevBinding,
                reason,
              );
            } else {
              throw new EnvError(binding, reason);
            }
          }
          if (binding.exclusive) {
            if (binding.origin != null) {
              const reason = `Attempts to set an exclusive environment variable but it was defined before.`;
              throw new BuildEnvConflictError(
                binding.origin,
                binding,
                prevBinding,
                reason,
              );
            } else {
              const reason =
                'Attempts to override a variable which is marked as exclusive';
              throw new EnvError(binding, reason);
            }
          }
        }
        env.index.set(binding.name, binding);
        env.env.push(binding);
      }
    }

    addToEnv(env, [
      {
        name: 'OCAMLPATH',
        value: OCAMLPATH.join(getPathsDelimiter('OCAMLPATH', config.buildPlatform)),
        builtIn: false,
        exclusive: true,
        origin: null,
      },
      {
        name: 'OCAMLFIND_DESTDIR',
        value: config.getInstallPath(spec, 'lib'),
        builtIn: false,
        exclusive: true,
        origin: null,
      },
      {
        name: 'OCAMLFIND_LDCONF',
        value: 'ignore',
        builtIn: false,
        exclusive: true,
        origin: null,
      },
      {
        name: 'OCAMLFIND_COMMANDS',
        // eslint-disable-next-line max-len
        value:
          'ocamlc=ocamlc.opt ocamldep=ocamldep.opt ocamldoc=ocamldoc.opt ocamllex=ocamllex.opt ocamlopt=ocamlopt.opt',
        builtIn: false,
        exclusive: true,
        origin: null,
      },
      {
        name: 'PATH',
        value: PATH.join(getPathsDelimiter('PATH', config.buildPlatform)),
        builtIn: false,
        exclusive: false,
        origin: null,
      },
      {
        name: 'MAN_PATH',
        value: MAN_PATH.join(getPathsDelimiter('MAN_PATH', config.buildPlatform)),
        builtIn: false,
        exclusive: false,
        origin: null,
      },

      // Esy builtins

      {
        name: `cur__name`,
        value: spec.name,
        origin: spec,
        builtIn: true,
        exclusive: true,
        origin: spec,
      },
      {
        name: `cur__version`,
        value: spec.version,
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
      {
        name: `cur__root`,
        value: config.getRootPath(spec),
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
      {
        name: `cur__depends`,
        value: Array.from(spec.dependencies.values(), dep => dep.name).join(' '),
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
      {
        name: `cur__target_dir`,
        value: config.getBuildPath(spec),
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
      {
        name: `cur__install`,
        value: config.getInstallPath(spec),
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
      {
        name: `cur__bin`,
        value: config.getInstallPath(spec, 'bin'),
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
      {
        name: `cur__sbin`,
        value: config.getInstallPath(spec, 'sbin'),
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
      {
        name: `cur__lib`,
        value: config.getInstallPath(spec, 'lib'),
        builtIn: true,
        exclusive: true,
        origin: spec,
      },
      {
        name: `cur__man`,
        value: config.getInstallPath(spec, 'man'),
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
      {
        name: `cur__doc`,
        value: config.getInstallPath(spec, 'doc'),
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
      {
        name: `cur__stublibs`,
        value: config.getInstallPath(spec, 'stublibs'),
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
      {
        name: `cur__toplevel`,
        value: config.getInstallPath(spec, 'toplevel'),
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
      {
        name: `cur__share`,
        value: config.getInstallPath(spec, 'share'),
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
      {
        name: `cur__etc`,
        value: config.getInstallPath(spec, 'etc'),
        origin: spec,
        builtIn: true,
        exclusive: true,
      },
    ]);

    // direct deps' local scopes
    for (const dep of dependencies.values()) {
      addToEnv(env, dep.env);
    }

    // all deps' global env
    for (const dep of allDependencies.values()) {
      addToEnv(env, dep.globalEnv);
    }

    // extra env
    if (params != null && params.env != null) {
      addToEnv(env, params.env);
    }

    const scope = getScope(spec, dependencies, config);
    const buildCommand = spec.buildCommand.map(command => renderCommand(command, scope));
    const installCommand = spec.installCommand.map(command =>
      renderCommand(command, scope),
    );

    const task = {
      id: spec.id,
      spec,
      buildCommand,
      installCommand,
      env: env.env,
      scope,
      dependencies: Map.mapValues(v => v.task, dependencies),
      errors: [],
    };

    return {task, env: scopes.env, globalEnv: scopes.globalEnv};
  }

  return task;
}

function getExportedEnv(
  config: Config<*>,
  dependencies: Map.Map<string, FoldState>,
  allDependencies: Map.Map<string, FoldState>,
  spec: BuildSpec,
): ExportedEnv {
  // scope which is used to eval exported variables
  const scope = getScope(spec, dependencies, config);

  // global env vars exported from a spec
  const globalEnv = [];

  // local env vars exported from a spec
  const env = [];

  let needCamlLdLibraryPathExport = true;

  for (const name in spec.exportedEnv) {
    const envConfig = spec.exportedEnv[name];
    const value = renderWithScope(envConfig.val, scope).rendered;
    const item = {
      name,
      value,
      origin: spec,
      builtIn: false,
      exclusive: Boolean(envConfig.exclusive),
    };
    if (envConfig.scope === 'global') {
      if (name === 'CAML_LD_LIBRARY_PATH') {
        needCamlLdLibraryPathExport = false;
      }
      globalEnv.push(item);
    } else {
      env.push(item);
    }
  }

  if (needCamlLdLibraryPathExport) {
    globalEnv.push({
      name: 'CAML_LD_LIBRARY_PATH',
      value: renderWithScope(
        `#{${spec.name}.stublibs : ${spec.name}.lib / 'stublibs' : $CAML_LD_LIBRARY_PATH}`,
        scope,
      ).rendered,
      origin: spec,
      builtIn: false,
      exclusive: false,
    });
  }

  return {env, globalEnv};
}

function renderCommand(command: Array<string> | string, scope) {
  if (Array.isArray(command)) {
    return {
      command: command.join(' '),
      renderedCommand: command
        .map(command => quoteArgIfNeeded(renderWithScope(command, scope).rendered))
        .join(' '),
    };
  } else {
    return {
      command,
      renderedCommand: renderWithScope(command, scope).rendered,
    };
  }
}

function getPackageScopeBindings(
  spec: BuildSpec,
  config: Config<path.Path>,
  currentlyBuilding?: boolean,
): BuildScope {
  const scope: BuildScope = Map.create(
    [
      {
        name: 'name',
        value: spec.name,
        origin: spec,
      },
      {
        name: 'version',
        value: spec.version,
        origin: spec,
      },
      {
        name: 'root',
        value: config.getRootPath(spec),
        origin: spec,
      },
      {
        name: 'depends',
        value: Array.from(spec.dependencies.values(), dep => dep.name).join(' '),
        origin: spec,
      },
      {
        name: 'target_dir',
        value: config.getBuildPath(spec),
        origin: spec,
      },
      {
        name: 'install',
        value: config.getFinalInstallPath(spec),
        origin: spec,
      },
      {
        name: 'bin',
        value: config.getFinalInstallPath(spec, 'bin'),
        origin: spec,
      },
      {
        name: 'sbin',
        value: config.getFinalInstallPath(spec, 'sbin'),
        origin: spec,
      },
      {
        name: 'lib',
        value: config.getFinalInstallPath(spec, 'lib'),
        origin: spec,
      },
      {
        name: 'man',
        value: config.getFinalInstallPath(spec, 'man'),
        origin: spec,
      },
      {
        name: 'doc',
        value: config.getFinalInstallPath(spec, 'doc'),
        origin: spec,
      },
      {
        name: 'stublibs',
        value: config.getFinalInstallPath(spec, 'stublibs'),
        origin: spec,
      },
      {
        name: 'toplevel',
        value: config.getFinalInstallPath(spec, 'toplevel'),
        origin: spec,
      },
      {
        name: 'share',
        value: config.getFinalInstallPath(spec, 'share'),
        origin: spec,
      },
      {
        name: 'etc',
        value: config.getFinalInstallPath(spec, 'etc'),
        origin: spec,
      },
    ].map(item => [item.name, item]),
  );
  return scope;
}

function getScope(
  spec: BuildSpec,
  dependencies: Map.Map<string, FoldState>,
  config,
): BuildScope {
  const scope: BuildScope = Map.create();

  for (const dep of dependencies.values()) {
    const depScope = getPackageScopeBindings(dep.task.spec, config);
    scope.set(dep.task.spec.name, depScope);
  }

  // Set own scope both under package name and `self` name for convenience.
  const selfScope = getPackageScopeBindings(spec, config);
  scope.set(spec.name, selfScope);
  scope.set('self', selfScope);

  return scope;
}

function resolveWithScope(id, scope) {
  let v = scope;
  for (let i = 0; i < id.length; i++) {
    if (!(v instanceof Map.Map)) {
      throw new Error(`Invalid reference: ${id.join('.')}`);
    }
    v = v.get(id[i]);
  }
  if (v instanceof Map.Map) {
    throw new Error(`Invalid reference: ${id.join('.')}`);
  }
  if (v == null) {
    throw new Error(`Invalid reference: ${id.join('.')}`);
  }
  return v.value;
}

export function renderWithScope(value: string, scope: BuildScope): {rendered: string} {
  const evaluator = {
    id: id => resolveWithScope(id, scope),
    var: name => '$' + name,
    pathSep: () => '/',
    colon: () => ':',
  };
  const rendered = CommandExpr.evaluate(value, evaluator);
  return {rendered};
}

/**
 * Logic to determine how file paths inside of env vars should be delimited.
 * For example, what separates file paths in the `PATH` env variable, or
 * `OCAMLPATH` variable? In an ideal world, the logic would be very simple:
 * `linux`/`darwin`/`cygwin` always uses `:`, and Windows/MinGW always uses
 * `;`, however there's some unfortunate edge cases to deal with - `esy` can
 * take care of all of that for you.
 */
function getPathsDelimiter(envVarName: string, buildPlatform: BuildPlatform) {
  // Error as a courtesy. This means something went wrong in the esy code, not
  // consumer code. Should be fixed ASAP.
  if (envVarName === '' || envVarName.charAt(0) === '$') {
    throw new Error('Invalidly formed environment variable:' + envVarName);
  }
  if (buildPlatform === null || buildPlatform === undefined) {
    throw new Error('Build platform not specified');
  }
  // Comprehensive pattern matching would be nice to have here!
  return envVarName === 'OCAMLPATH' && buildPlatform === 'cygwin'
    ? ';'
    : buildPlatform === 'cygwin' ||
      buildPlatform === 'linux' ||
      buildPlatform === 'darwin'
      ? ':'
      : ';';
}

export class EnvError extends errors.UsageError {
  constructor(binding: EnvironmentBinding, reason: string) {
    const envMessage = `${binding.name}=${binding.value}: ${reason}`;
    super(envMessage);
    lang.fixupErrorSubclassing(this, EnvError);
  }
}

export class BuildEnvExportError extends errors.BuildConfigError {
  constructor(spec: BuildSpec, binding: EnvironmentBinding, reason: string) {
    const message = outdent`
      While exporting \$${binding.name}:
      ${reason}
    `;
    super(spec, message);
    lang.fixupErrorSubclassing(this, BuildEnvExportError);
  }
}

export class BuildEnvConflictError extends errors.BuildConfigError {
  constructor(
    spec: BuildSpec,
    binding: EnvironmentBinding,
    conflictingBinding: EnvironmentBinding,
    reason: string,
  ) {
    let message;
    if (conflictingBinding.origin != null) {
      const conflSpec = conflictingBinding.origin;
      message = outdent`
      While exporting \$${binding.name}:
      Variable conflicts with \$${conflictingBinding.name} defined by ${conflSpec.name} (at ${conflSpec.packagePath}):
      ${reason}
    `;
    } else {
      message = outdent`
      While exporting \$${binding.name}:
      Variable conflicts with \$${conflictingBinding.name}:
      ${reason}
    `;
    }
    super(spec, message);
    lang.fixupErrorSubclassing(this, BuildEnvConflictError);
  }
}
