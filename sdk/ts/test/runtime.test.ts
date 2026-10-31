import assert from "node:assert/strict";
import { test } from "node:test";
import { jsx } from "../src/jsx-runtime.ts";
import { Button, Stack, Text } from "../src/components.ts";
import { useEffect, useMemo, useRef, useState } from "../src/hooks.ts";
import { call, mount, setSetting, setting } from "../src/runtime.ts";
import { fakeHost, tick } from "./helpers.ts";

function Counter() {
  const [n, setN] = useState(0);
  return jsx(Stack, {
    children: [jsx(Text, { text: `n=${n}` }), jsx(Button, { title: "+", onAction: () => setN((v) => v + 1) })],
  });
}

test("mount commits rev 1 as a full replace", () => {
  const shell = fakeHost();
  mount(jsx(Counter, {}), shell);
  assert.equal(shell.commits.length, 1);
  assert.equal(shell.commits[0].rev, 1);
  assert.equal(shell.commits[0].ops[0].op, "replace");
});

test("rev continues from the host after a reload", () => {
  const shell = fakeHost();
  shell.rev = 41;
  mount(jsx(Counter, {}), shell);
  assert.equal(shell.commits[0].rev, 42);
});

test("dispatch runs the handler; several state changes in one turn make one commit", async () => {
  const shell = fakeHost();
  mount(jsx(Counter, {}), shell);
  const button = shell.commits[0].ops[0].node.children[0].children[1].props.onAction;
  shell.dispatch!(button);
  shell.dispatch!(button);
  await tick();
  assert.equal(shell.commits.length, 2);
  assert.deepEqual(shell.commits[1].ops, [
    { op: "update", id: shell.commits[0].ops[0].node.children[0].children[0].id, props: { text: "n=2" } },
  ]);
});

test("resync lifecycle re-sends the whole tree with a new rev", () => {
  const shell = fakeHost();
  mount(jsx(Counter, {}), shell);
  shell.lifecycle!("resync");
  assert.equal(shell.commits[1].rev, 2);
  assert.equal(shell.commits[1].ops[0].op, "replace");
});

test("effects run after commit, clean up on dep change", async () => {
  const log: string[] = [];
  let bump = () => {};
  function Probe() {
    const [n, setN] = useState(0);
    bump = () => setN(n + 1);
    useEffect(() => {
      log.push(`on${n}`);
      return () => log.push(`off${n}`);
    }, [n]);
    return null;
  }
  mount(jsx(Probe, {}), fakeHost());
  assert.deepEqual(log, ["on0"]);
  bump();
  await tick();
  assert.deepEqual(log, ["on0", "off0", "on1"]);
});

test("useMemo and useRef keep values across renders", async () => {
  let computed = 0;
  let ref: { current: number } | undefined;
  let bump = () => {};
  function Probe() {
    const [n, setN] = useState(0);
    bump = () => setN(n + 1);
    useMemo(() => ++computed, [0]);
    const r = useRef(7);
    ref ??= r;
    assert.equal(r, ref);
    return null;
  }
  mount(jsx(Probe, {}), fakeHost());
  bump();
  await tick();
  assert.equal(computed, 1);
});

test("unmounted component effects are cleaned up", async () => {
  let cleaned = false;
  let hide = () => {};
  function Child() {
    useEffect(() => () => void (cleaned = true), []);
    return null;
  }
  function Parent() {
    const [shown, setShown] = useState(true);
    hide = () => setShown(false);
    return shown ? jsx(Child, {}) : null;
  }
  mount(jsx(Parent, {}), fakeHost());
  hide();
  await tick();
  assert.equal(cleaned, true);
});

test("call resolves with the result, forwards events, and exposes abort", async () => {
  const events: unknown[] = [];
  let cancelled = false;
  const shell = fakeHost();
  shell.call = (method, params, onEvent, onDone) => {
    assert.equal(method, "echo");
    assert.deepEqual(JSON.parse(params), { text: "hi" });
    onEvent('{"type":"text_delta","delta":"h"}');
    onDone('{"ok":true}', null);
    return () => void (cancelled = true);
  };
  mount(null, shell);
  const pending = call("echo", { text: "hi" }, { onEvent: (e) => events.push(e) });
  assert.deepEqual(await pending, { ok: true });
  assert.deepEqual(events, [{ type: "text_delta", delta: "h" }]);
  pending.abort();
  assert.equal(cancelled, true);
});

test("call rejects with the backend error code", async () => {
  const shell = fakeHost();
  shell.call = (_m, _p, _e, onDone) => {
    onDone(null, '{"code":"cancelled","message":"stopped"}');
    return () => {};
  };
  mount(null, shell);
  await assert.rejects(call("slow"), { code: "cancelled" });
});

test("settings round-trip JSON", () => {
  const shell = fakeHost();
  const store: Record<string, string> = {};
  shell.setting = (k) => store[k];
  shell.setSetting = (k, v) => void (store[k] = v);
  mount(null, shell);
  assert.equal(setting("auto", true), true);
  setSetting("auto", false);
  assert.equal(setting("auto", true), false);
});
