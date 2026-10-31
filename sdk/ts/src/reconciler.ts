import { Stream } from "./stream.ts";
import type { Child, Component, Key, Props, UINodeData, UIOp, VNode } from "./types.ts";

interface CompInst {
  kind: "comp";
  type: Component;
  key: string | undefined;
  hooks: unknown[];
  out: Slots;
  alive: boolean;
}

interface HostInst {
  kind: "host";
  type: string;
  key: string | undefined;
  id: string;
  props: Props;
  kids: Slots;
  alive: boolean;
}

type Inst = CompInst | HostInst;
/** `null` marks a hidden conditional child so the siblings after it keep their positions. */
type Slots = (Inst | null)[];

let current: { session: Session; comp: CompInst; index: number } | null = null;

/** The hook slot for the component being rendered; `init` runs on first render only. */
export function useHook<T extends object>(init: (comp: { alive: boolean }, session: Session) => T): T {
  if (!current) throw new Error("hooks can only be called while a component renders");
  const { session, comp } = current;
  return (comp.hooks[current.index++] ??= init(comp, session)) as T;
}

/** Runs after the commit that follows this render. */
export function defer(fn: () => void): void {
  current?.session.effects.push(fn);
}

export class Session {
  readonly ops: UIOp[] = [];
  readonly effects: (() => void)[] = [];
  private readonly handlers = new Map<string, (value: unknown) => void>();
  private readonly root: HostInst = {
    kind: "host",
    type: "App",
    key: undefined,
    id: "root",
    props: {},
    kids: [],
    alive: true,
  };
  private seq = 0;
  private queued = false;

  private readonly flush: () => void;

  constructor(flush: () => void) {
    this.flush = flush;
  }

  /** Batches state changes of one event-loop turn into a single flush. */
  schedule(): void {
    if (this.queued) return;
    this.queued = true;
    void Promise.resolve().then(() => {
      this.queued = false;
      this.flush();
    });
  }

  mount(element: Child): UIOp {
    this.root.kids = this.list([], expand(element));
    this.ops.length = 0;
    return this.snapshot();
  }

  /** Re-renders and returns the ops that turn the shell's tree into the new one (appends included). */
  render(element: Child): UIOp[] {
    const before = flat(this.root.kids);
    this.root.kids = this.list(this.root.kids, expand(element));
    this.diffKids(this.root, before, flat(this.root.kids));
    return this.ops.splice(0);
  }

  snapshot(): UIOp {
    return { op: "replace", node: toData(this.root) };
  }

  dispatch(handler: string, value: unknown): void {
    try {
      this.handlers.get(handler)?.(value);
    } catch (error) {
      console.error(`handler ${handler} threw: ${error}`);
    }
  }

  runEffects(): void {
    for (const run of this.effects.splice(0)) run();
  }

  private list(prev: Slots, next: (VNode | null)[]): Slots {
    const keyed = new Map<string, Inst>();
    for (const p of prev) if (p && p.key !== undefined) keyed.set(p.key, p);
    const used = new Set<Inst>();
    const out: Slots = [];
    for (let i = 0; i < next.length; i++) {
      const v = next[i];
      if (!v) {
        out.push(null);
        continue;
      }
      const key = keyOf(v.key);
      let found = (key !== undefined ? keyed.get(key) : prev[i]) ?? undefined;
      if (found && (found.key !== key || used.has(found) || !sameType(found, v))) found = undefined;
      if (found) used.add(found);
      out.push(typeof v.type === "function" ? this.comp(found as CompInst, v as VNode & { type: Component }) : this.host(found as HostInst, v as VNode & { type: string }));
    }
    for (const p of prev) if (p && !used.has(p)) this.unmount(p);
    return out;
  }

  private comp(prev: CompInst | undefined, v: VNode & { type: Component }): CompInst {
    const comp: CompInst = prev ?? {
      kind: "comp",
      type: v.type,
      key: keyOf(v.key),
      hooks: [],
      out: [],
      alive: true,
    };
    const outer = current;
    current = { session: this, comp, index: 0 };
    let output: Child;
    try {
      output = v.type(v.props);
    } finally {
      current = outer;
    }
    comp.out = this.list(comp.out, expand(output));
    return comp;
  }

  private host(prev: HostInst | undefined, v: VNode & { type: string }): HostInst {
    const host: HostInst = prev ?? {
      kind: "host",
      type: v.type,
      key: keyOf(v.key),
      id: `n${++this.seq}`,
      props: {},
      kids: [],
      alive: true,
    };
    const props = this.serialize(host, v.props);
    const before = prev ? flat(host.kids) : [];
    host.kids = this.list(host.kids, expand(v.props.children as Child));
    if (prev) {
      const changed = diffProps(host.props, props);
      if (changed) this.ops.push({ op: "update", id: host.id, props: changed });
      this.diffKids(host, before, flat(host.kids));
    }
    host.props = props;
    return host;
  }

  /** Mirrors the new child order with remove / move / insert against what the shell currently holds. */
  private diffKids(host: HostInst, before: HostInst[], after: HostInst[]): void {
    const keep = new Set(after);
    for (const old of before) if (!keep.has(old)) this.ops.push({ op: "remove", id: old.id });
    const shell = before.filter((n) => keep.has(n));
    for (let i = 0; i < after.length; i++) {
      const node = after[i]!;
      if (shell[i] === node) continue;
      const from = shell.indexOf(node);
      if (from >= 0) shell.splice(from, 1);
      shell.splice(i, 0, node);
      this.ops.push(
        from >= 0
          ? { op: "move", id: node.id, parent: host.id, index: i }
          : { op: "insert", parent: host.id, index: i, node: toData(node) },
      );
    }
  }

  /** Functions become handler ids (they stay here); streams bind to the node so `append` can find it. */
  private serialize(host: HostInst, raw: Props): Props {
    const props: Props = {};
    for (const [name, value] of Object.entries(raw)) {
      if (name === "children" || value === undefined) continue;
      if (typeof value === "function") {
        const handler = `${host.id}:${name}`;
        this.handlers.set(handler, value as (v: unknown) => void);
        props[name] = handler;
      } else if (value instanceof Stream) {
        value.bound = { host, prop: name, session: this };
        props[name] = value.value;
      } else {
        props[name] = value;
      }
    }
    return props;
  }

  private unmount(inst: Inst): void {
    inst.alive = false;
    if (inst.kind === "comp") {
      for (const hook of inst.hooks) (hook as { cleanup?: () => void }).cleanup?.();
      for (const child of inst.out) if (child) this.unmount(child);
      return;
    }
    for (const name of Object.keys(inst.props)) this.handlers.delete(`${inst.id}:${name}`);
    for (const child of inst.kids) if (child) this.unmount(child);
  }
}

export type { HostInst };

function keyOf(key: Key | undefined): string | undefined {
  return key === undefined ? undefined : String(key);
}

function sameType(inst: Inst, v: VNode): boolean {
  return inst.kind === "comp" ? inst.type === v.type : inst.type === v.type;
}

/** The host nodes under a slot list, looking through components. */
function flat(slots: Slots): HostInst[] {
  const out: HostInst[] = [];
  for (const slot of slots) {
    if (!slot) continue;
    if (slot.kind === "host") out.push(slot);
    else out.push(...flat(slot.out));
  }
  return out;
}

function toData(host: HostInst): UINodeData {
  return { id: host.id, type: host.type, props: host.props, children: flat(host.kids).map(toData) };
}

function expand(child: Child): (VNode | null)[] {
  if (child === null || child === undefined || typeof child === "boolean") return [null];
  if (typeof child === "string" || typeof child === "number") {
    return [{ type: "Text", props: { text: String(child) }, key: undefined }];
  }
  if (Array.isArray(child)) return child.flatMap((c) => expand(c));
  return [child as VNode];
}

function diffProps(before: Props, after: Props): Props | null {
  const changed: Props = {};
  let any = false;
  for (const [name, value] of Object.entries(after)) {
    if (JSON.stringify(before[name]) !== JSON.stringify(value)) {
      changed[name] = value;
      any = true;
    }
  }
  for (const name of Object.keys(before)) {
    if (!(name in after)) {
      changed[name] = null;
      any = true;
    }
  }
  return any ? changed : null;
}
