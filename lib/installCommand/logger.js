/**
 * @flow
 */

import {type ReadStream} from 'fs';
import observatory from 'observatory';
import chalk from 'chalk';

observatory.settings({ prefix: '', width: 74 })

export default function initLogger(streamParser: ReadStream) {
  let tasks = {}

  function getTask(pkgRawSpec, pkg) {
    let packageName = pkg.name;
    let key = pkgRawSpec || packageName;
    if (tasks[key] == null) {
      let logName = chalk.white(`*** ${packageName} `);
      let logSpec = (pkgRawSpec || '');
      let task = observatory
        .add(logName + logSpec)
        .status(chalk.gray('·'));
      tasks[key] = task
    }
    return tasks[key];
  }

  streamParser.on('data', obj => {
    switch (obj.name) {
      case 'pnpm:progress':
        reportProgress(obj)
        return
      case 'pnpm:lifecycle':
        reportLifecycle(obj)
        return
      case 'pnpm:install-check':
        reportInstallCheck(obj)
        return
      case 'pnpm:registry':
        if (obj.level === 'warn') {
          printWarn(obj['message'])
        }
        return
      default:
        if (obj.level === 'debug') {
          return;
        } else if (obj.name !== 'pnpm' && obj.name.indexOf('pnpm:') !== 0) {
          return;
        } else if (obj.level === 'warn') {
          printWarn(obj['message'])
        } else if (obj.level === 'error') {
          console.log(chalk.red('ERROR'), obj['err'] && obj['err'].message || obj['message'])
        } else {
          console.log(obj['message'])
        }
    }
  })

  function reportProgress (logObj) {
    // lazy get task

    function t () {
      return getTask(logObj.pkg.rawSpec, logObj.pkg)
    }

    // the first thing it (probably) does is wait in queue to query the npm registry

    switch (logObj.status) {
      case 'resolving':
        t().status(chalk.yellow('finding ·'))
        return
      case 'download-queued':
        if (logObj.pkg.version) {
          t().status(chalk.gray('queued ' + logObj.pkg.version + ' ↓'))
          return
        }
        t().status(chalk.gray('queued ↓'))
        return
      case 'downloading':
      case 'download-start':
        if (logObj.pkg.version) {
          t().status(chalk.yellow('downloading ' + logObj.pkg.version + ' ↓'))
        } else {
          t().status(chalk.yellow('downloading ↓'))
        }
        if (logObj.downloadStatus && logObj.downloadStatus.total && logObj.downloadStatus.done < logObj.downloadStatus.total) {
          t().details('' + Math.round(logObj.downloadStatus.done / logObj.downloadStatus.total * 100) + '%')
        } else {
          t().details('')
        }
        return
      case 'done':
        if (logObj.pkg.version) {
          t().status(chalk.green('' + logObj.pkg.version + ' ✓'))
            .details('')
          return
        }
        t().status(chalk.green('OK ✓')).details('')
        return
      case 'dependencies':
        t().status(chalk.gray('' + logObj.pkg.version + ' ·'))
          .details('')
        return
      case 'error':
        t().status(chalk.red('ERROR ✗'))
          .details('')
        return
      default:
        t().status(logObj.status)
          .details('')
        return
    }
  }
}

function reportLifecycle (logObj) {
  if (logObj.level === 'error') {
    console.log(chalk.blue(logObj.pkgId) + '! ' + chalk.gray(logObj.line))
    return
  }
  console.log(chalk.blue(logObj.pkgId) + '  ' + chalk.gray(logObj.line))
}

function reportInstallCheck (logObj) {
  switch (logObj.code) {
    case 'EBADPLATFORM':
      printWarn(`Unsupported system. Skipping dependency ${logObj.pkgId}`)
      break
    case 'ENOTSUP':
      console.warn(logObj)
      break
  }
}

function printWarn (message: string) {
  console.log(chalk.yellow('WARN'), message)
}
