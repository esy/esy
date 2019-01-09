type t;

/**
 * Create a task queue.
 *
 * No more than `concurrency` number of tasks will be running at any time.
 */

let create: (~concurrency: int, unit) => t;

/**
 * Submit a task to the queue.
 */

let submit: (t, unit => Lwt.t('a)) => Lwt.t('a);

let queued: (t, unit => Lwt.t('a), unit) => Lwt.t('a);
