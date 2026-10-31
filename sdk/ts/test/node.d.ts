// Just the slice of node:test / node:assert the tests use; avoids a @types/node dependency.
declare module "node:test" {
  export function test(name: string, fn: () => void | Promise<void>): void;
}
declare module "node:assert/strict" {
  const assert: {
    deepEqual(actual: unknown, expected: unknown): void;
    equal(actual: unknown, expected: unknown): void;
    ok(value: unknown): void;
    rejects(promise: Promise<unknown>, expected: { code: string }): Promise<void>;
  };
  export default assert;
}
