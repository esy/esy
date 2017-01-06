/**
 * Utilities for programmatic Makefile genetation.
 *
 * @flow
 */


const outdent = require('outdent');

export type MakeRule = {
  type: 'rule';
  target: string;
  command?: ?string;
  phony?: boolean;
  dependencies?: Array<string>;
  exportEnv?: Array<string>;
};

export type MakeDefine = {
  type: 'define';
  name: string;
  value: string;
};

export type MakeFile = {
  type: 'file';
  target?: string;
  filename: string;
  dependencies?: Array<string>;
  value: string;
};

export type MakeRawItem = {|
  type: 'raw';
  value: string;
|};

export type MakeItem =
  | MakeRule
  | MakeFile
  | MakeDefine
  | MakeRawItem;

function renderMakefile(items: Array<MakeItem>) {
  return items
    .map(item => {
      if (item.type === 'rule') {
        return renderMakeRule(item);
      } else if (item.type === 'define') {
        return renderMakeDefine(item);
      } else if (item.type === 'raw') {
        return renderMakeRawItem(item);
      } else if (item.type === 'file') {
        return renderMakeFile(item);
      } else {
        throw new Error('Unknown make item:' + JSON.stringify(item));
      }
    })
    .join('\n\n');
}

function renderMakeDefine({name, value}) {
  return `define ${name}\n${escapeEnvVar(value)}\nendef`;
}

function renderMakeFile({filename, value, target, dependencies = []}) {
  let id = escapeName(filename);
  let output = outdent`
    define ${id}__CONTENTS
    ${escapeEnvVar(value)}
    endef

    export ${id}__CONTENTS

    .PHONY: ${filename}
    ${filename}: SHELL=/bin/bash
    ${filename}: ${dependencies.join(' ')}
    \tmkdir -p $(@D)
    \tprintenv "${id}__CONTENTS" > $(@)
  `;
  if (target) {
    output = output + `\n${target}: ${filename}`;
  }
  return output;
}

function renderMakeRawItem({value}) {
  return value;
}

function renderMakeRule(rule) {
  let {
    target,
    dependencies = [],
    command,
    phony,
    exportEnv,
  } = rule;
  let header = `${target}: ${dependencies.join(' ')}`;

  let prelude = '';
  if (exportEnv) {
    exportEnv.forEach(name => {
      prelude = prelude + `export ${name}\n`;
    });
  }

  if (phony) {
    prelude = prelude + `.PHONY: ${target}\n`;
  }

  if (command != null) {
    let recipe = escapeEnvVar(renderMakeRuleCommand({command}));
    return `${prelude}${header}\n${recipe}`;
  } else {
    return prelude + header;
  }
}

function renderMakeRuleCommand({command}) {
  command = command.split('\n').map(line => `\t${line}`).join('\n');
  return command;
}

function escapeEnvVar(command) {
  return command.replace(/\$([^\(])/g, '$$$$$1');
}

function escapeName(name) {
  return name.replace(/[^a-zA-Z0-9]/g, '_').replace(/_+/g, '_');
}

module.exports = {
  renderMakefile
};
