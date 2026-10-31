import assert from "node:assert/strict";
import { test } from "node:test";
import { jsx } from "../src/jsx-runtime.ts";
import { Stack, Text } from "../src/components.ts";
import { Stream } from "../src/stream.ts";
import { renderer, stack, text } from "./helpers.ts";

test("first render is one replace with stable ids", () => {
  const r = renderer(() => stack([text("a"), text("b")]));
  const [op] = r.next();
  assert.equal(op!.op, "replace");
  const tree = (op as any).node;
  assert.equal(tree.type, "App");
  assert.equal(tree.children[0].type, "Stack");
  assert.deepEqual(
    tree.children[0].children.map((c: any) => c.props.text),
    ["a", "b"],
  );
});

test("unchanged render emits nothing", () => {
  const r = renderer(() => stack([text("a")]));
  r.next();
  assert.deepEqual(r.next(), []);
});

test("changed prop emits a minimal update, removed prop emits null", () => {
  let label = "a";
  let style: string | undefined = "title";
  const r = renderer(() => jsx(Text, { text: label, style }));
  r.next();
  label = "b";
  style = undefined;
  const ops = r.next();
  assert.equal(ops.length, 1);
  assert.deepEqual((ops[0] as any).props, { text: "b", style: null });
});

const stackOf = (op: any) => op.node.children[0];

test("keyed children reorder with a move and keep ids", () => {
  let order = ["a", "b", "c"];
  const r = renderer(() => stack(order.map((k) => text(k, k))));
  const parent = stackOf(r.next()[0]);
  const id = Object.fromEntries(parent.children.map((n: any) => [n.props.text, n.id]));
  order = ["c", "a", "b"];
  assert.deepEqual(r.next(), [{ op: "move", id: id.c, parent: parent.id, index: 0 }]);
});

test("keyed insert and remove", () => {
  let order = ["a", "b"];
  const r = renderer(() => stack(order.map((k) => text(k, k))));
  const parent = stackOf(r.next()[0]);
  const [a] = parent.children;
  order = ["a", "x", "b"];
  const inserted = r.next() as any[];
  assert.equal(inserted.length, 1);
  assert.deepEqual([inserted[0].op, inserted[0].index, inserted[0].node.props.text], ["insert", 1, "x"]);
  order = ["b"];
  const removed = r.next() as any[];
  assert.deepEqual(
    removed.map((o) => o.op),
    ["remove", "remove"],
  );
  assert.ok(removed.some((o) => o.id === a.id));
});

test("unkeyed children are matched by position", () => {
  let items = ["a", "b"];
  const r = renderer(() => stack(items.map((t) => text(t))));
  r.next();
  items = ["a", "c"];
  const ops = r.next();
  assert.equal(ops.length, 1);
  assert.equal((ops[0] as any).op, "update");
  assert.deepEqual((ops[0] as any).props, { text: "c" });
});

test("a hidden conditional child keeps later siblings in place", () => {
  let show = true;
  const r = renderer(() => stack([show ? text("x") : null, text("y")]));
  r.next();
  show = false;
  const ops = r.next();
  assert.equal(ops.length, 1);
  assert.equal(ops[0]!.op, "remove");
});

test("stream append goes out as an append op and is not re-sent by the next diff", () => {
  const stream = new Stream("he");
  const r = renderer(() => jsx(Text, { text: stream }));
  const root = (r.next()[0] as any).node;
  const id = root.children[0].id;
  stream.append("llo");
  assert.deepEqual(r.next(), [{ op: "append", id, prop: "text", value: "llo" }]);
  assert.deepEqual(r.next(), []);
});

test("Fragment-like arrays flatten and text children become Text nodes", () => {
  const r = renderer(() => jsx(Stack, { children: ["hello", [text("a"), text("b")]] }));
  const kids = (r.next()[0] as any).node.children[0].children;
  assert.deepEqual(
    kids.map((k: any) => k.props.text),
    ["hello", "a", "b"],
  );
});
