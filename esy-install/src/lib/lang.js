/**
 * @flow
 */

export function fixupErrorSubclassing(instance: any, constructor: Function) {
  instance.constructor = constructor;
  instance.__proto__ = constructor.prototype;
}
