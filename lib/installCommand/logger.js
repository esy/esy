'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.default = initLogger;

require('fs');

var _observatory = require('observatory');

var _observatory2 = _interopRequireDefault(_observatory);

var _chalk = require('chalk');

var _chalk2 = _interopRequireDefault(_chalk);

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

_observatory2.default.settings({ prefix: '', width: 74 });

function initLogger(streamParser) {
  let tasks = {};

  function getTask(pkgRawSpec, pkg) {
    let packageName = pkg.name;
    let key = pkgRawSpec || packageName;
    if (tasks[key] == null) {
      let logName = _chalk2.default.white(`*** ${packageName} `);
      let logSpec = pkgRawSpec || '';
      let task = _observatory2.default.add(logName + logSpec).status(_chalk2.default.gray('·'));
      tasks[key] = task;
    }
    return tasks[key];
  }

  streamParser.on('data', obj => {
    switch (obj.name) {
      case 'pnpm:progress':
        reportProgress(obj);
        return;
      case 'pnpm:lifecycle':
        reportLifecycle(obj);
        return;
      case 'pnpm:install-check':
        reportInstallCheck(obj);
        return;
      case 'pnpm:registry':
        if (obj.level === 'warn') {
          printWarn(obj['message']);
        }
        return;
      default:
        if (obj.level === 'debug') {
          return;
        } else if (obj.name !== 'pnpm' && obj.name.indexOf('pnpm:') !== 0) {
          return;
        } else if (obj.level === 'warn') {
          printWarn(obj['message']);
        } else if (obj.level === 'error') {
          console.log(_chalk2.default.red('ERROR'), obj['err'] && obj['err'].message || obj['message']);
        } else {
          console.log(obj['message']);
        }
    }
  });

  function reportProgress(logObj) {
    // lazy get task

    function t() {
      return getTask(logObj.pkg.rawSpec, logObj.pkg);
    }

    // the first thing it (probably) does is wait in queue to query the npm registry

    switch (logObj.status) {
      case 'resolving':
        t().status(_chalk2.default.yellow('finding ·'));
        return;
      case 'download-queued':
        if (logObj.pkg.version) {
          t().status(_chalk2.default.gray('queued ' + logObj.pkg.version + ' ↓'));
          return;
        }
        t().status(_chalk2.default.gray('queued ↓'));
        return;
      case 'downloading':
      case 'download-start':
        if (logObj.pkg.version) {
          t().status(_chalk2.default.yellow('downloading ' + logObj.pkg.version + ' ↓'));
        } else {
          t().status(_chalk2.default.yellow('downloading ↓'));
        }
        if (logObj.downloadStatus && logObj.downloadStatus.total && logObj.downloadStatus.done < logObj.downloadStatus.total) {
          t().details('' + Math.round(logObj.downloadStatus.done / logObj.downloadStatus.total * 100) + '%');
        } else {
          t().details('');
        }
        return;
      case 'done':
        if (logObj.pkg.version) {
          t().status(_chalk2.default.green('' + logObj.pkg.version + ' ✓')).details('');
          return;
        }
        t().status(_chalk2.default.green('OK ✓')).details('');
        return;
      case 'dependencies':
        t().status(_chalk2.default.gray('' + logObj.pkg.version + ' ·')).details('');
        return;
      case 'error':
        t().status(_chalk2.default.red('ERROR ✗')).details('');
        return;
      default:
        t().status(logObj.status).details('');
        return;
    }
  }
}

function reportLifecycle(logObj) {
  if (logObj.level === 'error') {
    console.log(_chalk2.default.blue(logObj.pkgId) + '! ' + _chalk2.default.gray(logObj.line));
    return;
  }
  console.log(_chalk2.default.blue(logObj.pkgId) + '  ' + _chalk2.default.gray(logObj.line));
}

function reportInstallCheck(logObj) {
  switch (logObj.code) {
    case 'EBADPLATFORM':
      printWarn(`Unsupported system. Skipping dependency ${logObj.pkgId}`);
      break;
    case 'ENOTSUP':
      console.warn(logObj);
      break;
  }
}

function printWarn(message) {
  console.log(_chalk2.default.yellow('WARN'), message);
}
