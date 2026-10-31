export type Key = string | number;
export type Props = Record<string, unknown>;
export type Child = VNode | string | number | boolean | null | undefined | readonly Child[];
export type Component<P = any> = ((props: P) => Child) & { hostType?: string };

export interface VNode {
  readonly type: string | Component;
  readonly props: Props;
  readonly key: Key | undefined;
}

export interface UINodeData {
  id: string;
  type: string;
  props: Props;
  children: UINodeData[];
}

/** Wire ops, see docs/02-app-protocol.md §2.3. */
export type UIOp =
  | { op: "replace"; node: UINodeData }
  | { op: "insert"; parent: string; index: number; node: UINodeData }
  | { op: "remove"; id: string }
  | { op: "move"; id: string; parent: string; index: number }
  | { op: "update"; id: string; props: Props }
  | { op: "append"; id: string; prop: string; value: string };

/**
 * The `__wisp` object. Everything crossing it is a JSON string, so the shell never shares
 * JS objects with another thread. `call` returns the cancel function.
 */
export interface Host {
  /** First revision to use; non-zero after a hot reload so the shell does not drop our patches. */
  rev?: number;
  commit(patch: string): void;
  call(
    method: string,
    params: string,
    onEvent: (event: string) => void,
    onDone: (result: string | null, error: string | null) => void,
  ): () => void;
  setting(key: string): string | null | undefined;
  setSetting(key: string, value: string): void;
  dispatch?: (handler: string, value?: string) => void;
  lifecycle?: (kind: string) => void;
}
