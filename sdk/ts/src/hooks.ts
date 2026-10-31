import { useCallback, useEffect, useRef, useState } from "preact/hooks";
import { registerCommands, setting, setSetting, type CommandSpec } from "./bridge.ts";

export { useCallback, useEffect, useMemo, useRef, useState } from "preact/hooks";

/** A setting backed by the shell's per-app store; shows `fallback` until the stored value arrives. */
export function usePersisted<T>(key: string, fallback: T): [T, (value: T) => void] {
  const [value, setValue] = useState(fallback);
  useEffect(() => {
    void setting(key, fallback).then(setValue);
  }, [key]);
  const save = useCallback(
    (next: T) => {
      setSetting(key, next);
      setValue(next);
    },
    [key],
  );
  return [value, save];
}

/** Text that grows by `append`; re-renders at most once per frame however fast deltas arrive. */
export function useStream(initial = ""): { text: string; append(delta: string): void; set(value: string): void } {
  const [text, setText] = useState(initial);
  const buffer = useRef(initial);
  const frame = useRef(0);
  const push = useCallback(() => {
    frame.current ||= requestAnimationFrame(() => {
      frame.current = 0;
      setText(buffer.current);
    });
  }, []);
  return {
    text,
    append(delta) {
      buffer.current += delta;
      push();
    },
    set(value) {
      buffer.current = value;
      push();
    },
  };
}

/** Registers menu-bar commands while the component is mounted. */
export function useCommands(commands: CommandSpec[]): void {
  const key = JSON.stringify(commands.map(({ run: _run, ...rest }) => rest));
  const latest = useRef(commands);
  latest.current = commands;
  useEffect(() => {
    registerCommands(latest.current.map((c, i) => ({ ...c, run: () => latest.current[i]?.run() })));
  }, [key]);
}
