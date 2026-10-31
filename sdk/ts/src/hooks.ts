import { defer, useHook } from "./reconciler.ts";
import { Stream } from "./stream.ts";

type Deps = readonly unknown[];

const same = (a: Deps | undefined, b: Deps) => !!a && a.length === b.length && a.every((v, i) => Object.is(v, b[i]));

export function useState<T>(initial: T | (() => T)): [T, (next: T | ((prev: T) => T)) => void] {
  const slot = useHook((comp, session) => {
    const slot = {
      value: typeof initial === "function" ? (initial as () => T)() : initial,
      set(next: T | ((prev: T) => T)) {
        const value = typeof next === "function" ? (next as (p: T) => T)(slot.value) : next;
        if (!comp.alive || Object.is(value, slot.value)) return;
        slot.value = value;
        session.schedule();
      },
    };
    return slot;
  });
  return [slot.value, slot.set];
}

/** Runs after the commit; without deps, after every render. The returned function cleans up. */
export function useEffect(effect: () => void | (() => void), deps?: Deps): void {
  const slot = useHook(() => ({ ran: false, deps: undefined as Deps | undefined, cleanup: undefined as (() => void) | undefined }));
  if (slot.ran && deps && same(slot.deps, deps)) return;
  slot.ran = true;
  slot.deps = deps;
  defer(() => {
    slot.cleanup?.();
    slot.cleanup = effect() ?? undefined;
  });
}

export function useMemo<T>(compute: () => T, deps: Deps): T {
  const slot = useHook(() => ({ deps: undefined as Deps | undefined, value: undefined as T }));
  if (!same(slot.deps, deps)) {
    slot.value = compute();
    slot.deps = deps;
  }
  return slot.value;
}

export function useRef<T>(initial: T): { current: T } {
  return useHook(() => ({ current: initial }));
}

/** One stream per component instance; pass it as a prop value and `append` to it. */
export function useStream(initial = ""): Stream {
  return useHook(() => new Stream(initial));
}
