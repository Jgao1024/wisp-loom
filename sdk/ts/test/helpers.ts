import { jsx } from "../src/jsx-runtime.ts";
import { Session } from "../src/reconciler.ts";
import type { Child, Host, UIOp } from "../src/types.ts";
import { Stack, Text } from "../src/components.ts";

export const stack = (children: Child, key?: string) => jsx(Stack, { children }, key);
export const text = (value: string, key?: string) => jsx(Text, { text: value }, key);

/** Drives a Session synchronously: render, return the ops. */
export function renderer(view: () => Child) {
  const session = new Session(() => {});
  let first = true;
  return {
    session,
    next(): UIOp[] {
      if (first) {
        first = false;
        return [session.mount(view())];
      }
      return session.render(view());
    },
  };
}

export const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 0));

export function fakeHost(): Host & { commits: any[] } {
  const commits: any[] = [];
  return {
    commits,
    commit: (patch) => commits.push(JSON.parse(patch)),
    call: () => () => {},
    setting: () => null,
    setSetting: () => {},
  };
}
