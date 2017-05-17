/**
 * @flow
 */

import invariant from 'invariant';
import * as path from 'path';
import * as fs from './fs';

export type FileNode = {
  type: 'file',
  name: string,
  content: ?any,
};

export type LinkNode = {
  type: 'link',
  name: string,
  realpath: string,
};

export type DirectoryNode = {
  type: 'directory',
  name: string,
  nodes: Node[],
};

export type Node = FileNode | LinkNode | DirectoryNode;

export function file(name: string, content: ?any): FileNode {
  return {type: 'file', name, content};
}

export function link(name: string, realpath: string): LinkNode {
  return {type: 'link', name, realpath};
}

export function directory(name: string, nodes: Node[]): DirectoryNode {
  return {type: 'directory', name, nodes};
}

export async function write(rootDirname: string, nodes: Node[]): Promise<void> {
  invariant((await fs.readdir(rootDirname)).length === 0, 'Directory is not empty');

  async function writeFile(pathname: string, node: FileNode) {
    const content = typeof node.content === 'string' || node.content instanceof Buffer
      ? node.content
      : JSON.stringify(node.content);
    await fs.writeFile(pathname, content);
  }

  async function writeLink(pathname: string, node: LinkNode) {
    await fs.symlink(path.resolve(node.realpath, rootDirname), pathname);
  }

  async function writeDirectory(pathname: string, node: DirectoryNode) {
    await fs.mkdirp(pathname);
    const tasks = [];
    for (const nextNode of node.nodes) {
      const nextPathname = path.join(pathname, nextNode.name);
      if (nextNode.type === 'file') {
        tasks.push(writeFile(nextPathname, nextNode));
      } else if (nextNode.type === 'link') {
        tasks.push(writeLink(nextPathname, nextNode));
      } else if (nextNode.type === 'directory') {
        tasks.push(writeDirectory(nextPathname, nextNode));
      }
    }
    await Promise.all(tasks);
  }

  await writeDirectory(rootDirname, {type: 'directory', name: '<root>', nodes});
}

export async function read(rootDirname: string): Promise<Node[]> {
  function crawlFile(pathname: string, name: string): Promise<FileNode> {
    return Promise.resolve({
      type: 'file',
      name,
      content: null,
    });
  }

  async function crawlLink(pathname: string, name: string): Promise<LinkNode> {
    const realpath = path.relative(await fs.realpath(pathname), rootDirname);
    return {
      type: 'link',
      name,
      realpath,
    };
  }

  async function crawlDirectory(pathname: string, name: string): Promise<DirectoryNode> {
    const tasks = [];
    for (const name of await fs.readdir(pathname)) {
      const nextPathname = path.join(pathname, name);
      const stat = await fs.stat(nextPathname);
      if (stat.isSymbolicLink()) {
        tasks.push(crawlLink(nextPathname, name));
      } else if (stat.isFile()) {
        tasks.push(crawlFile(nextPathname, name));
      } else if (stat.isDirectory()) {
        tasks.push(crawlDirectory(nextPathname, name));
      }
    }
    const nodes = await Promise.all(tasks);
    nodes.sort((a, b) => a.name.localeCompare(b.name));
    return {type: 'directory', name, nodes};
  }

  const {nodes} = await crawlDirectory(rootDirname, '<root>');
  return nodes;
}
