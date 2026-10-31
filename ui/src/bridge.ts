/** Page ↔ host messages. Everything is JSON; the host is Swift (docs/02-app-protocol.md §2). */

declare global {
  interface Window {
    __wisp_boot: Boot;
    __wisp_recv(batch: Incoming[]): void;
    webkit?: { messageHandlers: { wisp: { postMessage(json: string): void } } };
  }
}

export interface Boot {
  appID: string;
  lang: string;
  title: string;
  hasBackend: boolean;
  window: "main" | "settings";
}

type Reply = { type: "reply"; id: number; result?: unknown; event?: unknown; error?: { code: string; message: string } };
type Incoming =
  | Reply
  | { type: "command"; id: string }
  | { type: "toolbarAction"; id: string }
  | { type: "toolbarSearch"; text: string }
  | { type: "tabSelected"; id: string };

export const boot: Boot = window.__wisp_boot ?? { appID: "dev", lang: "en", title: "", hasBackend: false, window: "main" };

export function post(message: object): void {
  window.webkit?.messageHandlers.wisp.postMessage(JSON.stringify(message));
}

interface Waiting {
  resolve(value: unknown): void;
  reject(error: Error): void;
  onEvent?: (event: any) => void;
}

const waiting = new Map<number, Waiting>();
const commandHandlers = new Map<string, () => void>();
let toolbarActions: ((id: string) => void) | undefined;
let toolbarSearchHandler: ((text: string) => void) | undefined;
let tabHandler: ((id: string) => void) | undefined;
let seq = 0;

window.__wisp_recv = (batch) => {
  for (const message of batch as Incoming[]) {
    if (message.type === "command") {
      commandHandlers.get(message.id)?.();
      continue;
    }
    if (message.type === "toolbarAction") {
      toolbarActions?.(message.id);
      continue;
    }
    if (message.type === "toolbarSearch") {
      toolbarSearchHandler?.(message.text);
      continue;
    }
    if (message.type === "tabSelected") {
      tabHandler?.(message.id);
      continue;
    }
    const call = waiting.get(message.id);
    if (!call) continue;
    if (message.event !== undefined) {
      call.onEvent?.(message.event);
      continue;
    }
    waiting.delete(message.id);
    if (message.error) call.reject(new CallError(message.error.code, message.error.message));
    else call.resolve(message.result);
  }
};

export class CallError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

export interface Call<T> extends Promise<T> {
  /** Asks the backend to cancel; the promise then rejects with code `cancelled`. */
  abort(): void;
}

/** Calls a backend method (or a `shell.*` capability). Events arrive through `onEvent` while it runs. */
export function call<T = unknown>(method: string, params: unknown = {}, options: { onEvent?: (event: any) => void } = {}): Call<T> {
  const id = ++seq;
  const promise = new Promise<T>((resolve, reject) => {
    waiting.set(id, { resolve: resolve as (v: unknown) => void, reject, onEvent: options.onEvent });
    post({ type: "call", id, method, params });
  });
  return Object.assign(promise, { abort: () => post({ type: "cancel", id }) });
}

/** Per-app settings kept by the shell (UserDefaults), JSON values. */
export function setting<T>(key: string, fallback: T): Promise<T> {
  const id = ++seq;
  return new Promise<T>((resolve) => {
    waiting.set(id, { resolve: (v) => resolve(v === null || v === undefined ? fallback : (v as T)), reject: () => resolve(fallback) });
    post({ type: "setting", id, key });
  });
}

export function setSetting(key: string, value: unknown): void {
  post({ type: "setSetting", key, value });
}

/** Secrets are write-only from the page; only the backend can read them back. */
export const setSecret = (key: string, value: string) => call("shell.secret.set", { key, value });
export const deleteSecret = (key: string) => call("shell.secret.delete", { key });

export const log = (text: string) => post({ type: "log", text });
export const setWindowTitle = (title: string, subtitle?: string) => post({ type: "title", title, subtitle });
export const openSettings = () => post({ type: "openSettings" });
/** For settings windows: the content height the window should animate to. */
export const setContentHeight = (value: number) => post({ type: "height", value });

export interface CommandSpec {
  id: string;
  menu: "file" | "view";
  title: string;
  shortcut?: string;
  disabled?: boolean;
  run: () => void;
}

/** Replaces this app's menu-bar commands. */
export function registerCommands(commands: CommandSpec[]): void {
  commandHandlers.clear();
  for (const c of commands) commandHandlers.set(c.id, c.run);
  post({ type: "commands", commands: commands.map(({ run: _run, ...rest }) => rest) });
}

export interface ToolbarMenuItem {
  id: string;
  title: string;
  destructive?: boolean;
  disabled?: boolean;
}

export interface ToolbarItem {
  id: string;
  symbol?: string;
  title?: string;
  help?: string;
  disabled?: boolean;
  menu?: ToolbarMenuItem[];
  search?: boolean;
  sidebar?: boolean;
  placeholder?: string;
}

export interface ToolbarTab {
  id: string;
  title: string;
  symbol?: string;
  selected?: boolean;
}

/** A window toolbar: plain semantics only, every control is native (docs/06-native-toolbar.md §3). */
export interface ToolbarSpec {
  leading?: ToolbarItem[];
  trailing?: ToolbarItem[];
  tabs?: ToolbarTab[];
}

/** Sends this window's toolbar; the host rebuilds only when the structure changes. */
export function registerToolbar(spec: ToolbarSpec): void {
  post({ type: "toolbar", spec });
}

/** The latest toolbar handlers; host clicks and search text are routed here by id. */
export function setToolbarHandlers(action: (id: string) => void, search?: (text: string) => void): void {
  toolbarActions = action;
  toolbarSearchHandler = search;
}

/** The selected native toolbar tab; the page switches its pane and sends the new `selected` flag. */
export function setTabHandler(handler: (id: string) => void): void {
  tabHandler = handler;
}
