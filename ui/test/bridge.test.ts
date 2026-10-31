import assert from "node:assert/strict";
import { test } from "node:test";
import { answer, posted, take } from "./setup.ts";
import {
  call,
  CallError,
  deleteSecret,
  registerCommands,
  registerToolbar,
  setSecret,
  setTabHandler,
  setSetting,
  setToolbarHandlers,
  setting,
} from "../src/bridge.ts";

test("call posts a request and resolves with the result", async () => {
  take();
  const pending = call("echo", { text: "hi" });
  const [request] = take();
  assert.deepEqual({ ...request, id: 0 }, { type: "call", id: 0, method: "echo", params: { text: "hi" } });
  answer({ type: "reply", id: request.id, result: { ok: true } });
  assert.deepEqual(await pending, { ok: true });
});

test("events reach onEvent until the final reply", async () => {
  take();
  const events: unknown[] = [];
  const pending = call("stream", {}, { onEvent: (e) => events.push(e) });
  const [{ id }] = take();
  answer({ type: "reply", id, event: { type: "text_delta", delta: "a" } }, { type: "reply", id, event: { type: "text_delta", delta: "b" } });
  answer({ type: "reply", id, result: null });
  await pending;
  assert.deepEqual(events, [{ type: "text_delta", delta: "a" }, { type: "text_delta", delta: "b" }]);
});

test("errors reject with the backend code", async () => {
  take();
  const pending = call("x");
  const [{ id }] = take();
  answer({ type: "reply", id, error: { code: "http_401", message: "bad key" } });
  await assert.rejects(pending, { code: "http_401" });
  assert.ok(new CallError("a", "b") instanceof Error);
});

test("abort posts a cancel with the page's id", () => {
  take();
  const pending = call("slow");
  const [{ id }] = take();
  pending.abort();
  assert.deepEqual(take(), [{ type: "cancel", id }]);
  pending.catch(() => {});
});

test("two calls in flight are answered independently, in any order", async () => {
  take();
  const a = call("a");
  const b = call("b");
  const [first, second] = take();
  answer({ type: "reply", id: second.id, result: "B" });
  answer({ type: "reply", id: first.id, result: "A" });
  assert.deepEqual([await a, await b], ["A", "B"]);
});

test("setting resolves to the stored value or the fallback", async () => {
  take();
  const stored = setting("name", "fallback");
  const missing = setting("other", 7);
  const [one, two] = take();
  assert.deepEqual([one.type, one.key], ["setting", "name"]);
  answer({ type: "reply", id: one.id, result: "Hello" }, { type: "reply", id: two.id, result: null });
  assert.equal(await stored, "Hello");
  assert.equal(await missing, 7);
});

test("setSetting posts a setSetting message", () => {
  take();
  setSetting("showGroups", false);
  assert.deepEqual(take(), [{ type: "setSetting", key: "showGroups", value: false }]);
});

test("secrets are written through shell.secret.* calls, never read", () => {
  take();
  void setSecret("k", "v");
  void deleteSecret("k");
  const methods = take().map((m) => m.method);
  assert.deepEqual(methods, ["shell.secret.set", "shell.secret.delete"]);
});

test("registered commands post their spec and run on a command message", () => {
  take();
  let ran = 0;
  registerCommands([{ id: "new", menu: "file", title: "New", shortcut: "cmd+n", run: () => ran++ }]);
  assert.deepEqual(take(), [{ type: "commands", commands: [{ id: "new", menu: "file", title: "New", shortcut: "cmd+n" }] }]);
  answer({ type: "command", id: "new" });
  answer({ type: "command", id: "unknown" });
  assert.equal(ran, 1);
  assert.ok(posted.length === 0);
});

test("toolbar specs are posted and native actions/search reach the latest handlers", () => {
  take();
  const spec = {
    leading: [{ id: "new", symbol: "square.and.pencil", help: "New" }],
    trailing: [{ id: "search", search: true, placeholder: "Search" }],
  };
  registerToolbar(spec);
  assert.deepEqual(take(), [{ type: "toolbar", spec }]);

  const calls: string[] = [];
  setToolbarHandlers(() => calls.push("stale"), () => calls.push("stale search"));
  setToolbarHandlers((id) => calls.push(`action:${id}`), (text) => calls.push(`search:${text}`));
  answer({ type: "toolbarAction", id: "new" }, { type: "toolbarSearch", text: "abc" });
  assert.deepEqual(calls, ["action:new", "search:abc"]);
});

test("settings tabs are posted and the selected pane comes back by id", () => {
  take();
  const tabs = [
    { id: "general", title: "General", symbol: "gearshape", selected: true },
    { id: "models", title: "Models", symbol: "cpu" },
  ];
  registerToolbar({ tabs });
  assert.deepEqual(take(), [{ type: "toolbar", spec: { tabs } }]);

  const selected: string[] = [];
  setTabHandler((id) => selected.push("stale"));
  setTabHandler((id) => selected.push(id));
  answer({ type: "tabSelected", id: "models" });
  assert.deepEqual(selected, ["models"]);
});
