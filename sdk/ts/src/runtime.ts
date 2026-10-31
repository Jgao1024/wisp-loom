import { Session } from "./reconciler.ts";
import type { Child, Host, UIOp } from "./types.ts";

declare global {
  // Injected by the shell before ui.js runs.
  var __wisp: Host;
}

let active: Host | undefined;
const host = (): Host => (active ??= globalThis.__wisp);

/** Renders `root`, then re-renders on state changes; one `commit` per event-loop turn. */
export function mount(root: Child, shell: Host = globalThis.__wisp): void {
  active = shell;
  let rev = shell.rev ?? 0;
  const commit = (ops: UIOp[]) => {
    if (ops.length) shell.commit(JSON.stringify({ rev: ++rev, ops }));
  };
  const session = new Session(() => {
    try {
      commit(session.render(root));
    } catch (error) {
      console.error(`render failed: ${error}`);
    }
    session.runEffects();
  });
  commit([session.mount(root)]);
  session.runEffects();

  shell.dispatch = (handler, value) => session.dispatch(handler, value === undefined ? undefined : JSON.parse(value));
  // "resync": the shell rejected a patch and wants the whole tree.
  shell.lifecycle = (kind) => {
    if (kind === "resync") commit([session.snapshot()]);
  };
}

export interface CallOptions {
  onEvent?: (event: any) => void;
}

export interface Call<T> extends Promise<T> {
  /** Asks the backend to cancel; the promise then rejects with code `cancelled`. */
  abort(): void;
}

export class CallError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

/** Calls a backend method (or a `shell.*` capability). Events arrive through `onEvent` while it runs. */
export function call<T = unknown>(method: string, params: unknown = {}, options: CallOptions = {}): Call<T> {
  let cancel = () => {};
  const promise = new Promise<T>((resolve, reject) => {
    cancel = host().call(
      method,
      JSON.stringify(params),
      (event) => options.onEvent?.(JSON.parse(event)),
      (result, error) => {
        if (error === null) return resolve(result === null ? (undefined as T) : JSON.parse(result));
        const failure = JSON.parse(error);
        reject(new CallError(failure.code, failure.message));
      },
    );
  });
  return Object.assign(promise, { abort: () => cancel() });
}

export function setting<T>(key: string, fallback: T): T {
  const raw = host().setting(key);
  return raw === null || raw === undefined ? fallback : JSON.parse(raw);
}

export function setSetting(key: string, value: unknown): void {
  host().setSetting(key, JSON.stringify(value));
}

/** Secrets are write-only from the UI; only the backend can read them back. */
export const setSecret = (key: string, value: string) => call("shell.secret.set", { key, value });
export const deleteSecret = (key: string) => call("shell.secret.delete", { key });
