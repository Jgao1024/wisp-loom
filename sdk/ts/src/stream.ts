import type { HostInst, Session } from "./reconciler.ts";

/**
 * A text prop that grows by `append` ops instead of going through the diff: pass it as a prop
 * value (`<Text text={stream} />`) and call `append` for every delta.
 */
export class Stream {
  /** @internal set while a rendered node holds this stream */
  bound: { host: HostInst; prop: string; session: Session } | null = null;

  value: string;

  constructor(value = "") {
    this.value = value;
  }

  append(delta: string): void {
    this.value += delta;
    const b = this.bound;
    if (!b?.host.alive) return;
    b.host.props[b.prop] = this.value; // the next diff must not resend what append already carries
    b.session.ops.push({ op: "append", id: b.host.id, prop: b.prop, value: delta });
    b.session.schedule();
  }

  set(value: string): void {
    this.value = value;
    this.bound?.session.schedule();
  }
}
