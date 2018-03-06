/**
 * @flow
 */

import type {Config, Reporter} from './types';
import {
  ConsoleReporter as ConsoleReporterBase,
  NoopReporter,
} from '@esy-ocaml/esy-install/src/reporters';

import type {
  ReporterSpinner,
  ReporterSpinnerSet,
} from '@esy-ocaml/esy-install/src/reporters/types';

export class HighSeverityReporter extends NoopReporter {
  reporter: Reporter;

  constructor(reporter: Reporter) {
    super();
    this.reporter = reporter;
  }

  error(...args: string[]) {
    return this.reporter.error(...args);
  }
}

export class ConsoleReporter extends ConsoleReporterBase {
  activity(): ReporterSpinner {
    return {
      tick(name: string) {},
      end() {},
    };
  }

  activitySet(total: number, workers: number): ReporterSpinnerSet {
    if (!this.isTTY) {
      const logProgress = msg => this._log(`${this.format.blue('progress')} ${msg}`);
      const spinners = [];

      for (let i = 1; i <= total; i++) {
        spinners.push(createNoTTYSpinner({total, logProgress}));
      }
      return {
        spinners,
        end() {
          spinners.forEach(spinner => spinner.end());
        },
      };
    }
    return super.activitySet(total, workers);
  }
}

function createNoTTYSpinner({total, logProgress}) {
  let prefixState = null;
  const formatPrefix = () => {
    if (prefixState == null) {
      return '';
    } else {
      const {current, prefix} = prefixState;
      const totalS = String(total);
      const currentS = String(current).padStart(totalS.length, '0');
      return `[${currentS}/${totalS}] ${prefixState.prefix}`;
    }
  };

  return {
    clear() {},
    setPrefix(current, prefix) {
      if (prefixState != null) {
        logProgress(`${formatPrefix()}: completed`);
      }
      prefixState = {current, prefix};
      logProgress(`${formatPrefix()}: started`);
    },
    tick(msg) {
      logProgress(`${formatPrefix()}: ${msg}`);
    },
    end() {
      logProgress(`${formatPrefix()}: completed`);
    },
  };
}

export type {Reporter};
