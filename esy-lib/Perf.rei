/**

  Utilities for measuring perf.

 */;

/** Measure and log execution time. */

let measure: (~label: string, unit => 'a) => 'a;

/** Measure and log execution time of an Lwt promise. */

let measureLwt: (~label: string, unit => Lwt.t('a)) => Lwt.t('a);
