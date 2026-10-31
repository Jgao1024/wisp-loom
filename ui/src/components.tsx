import { render as mount, type ComponentChildren, type VNode } from "preact";
import { useEffect, useLayoutEffect, useRef, useState } from "preact/hooks";
import { boot, openSettings, setContentHeight, setWindowTitle, showContextMenu } from "./bridge.ts";
import { useTabs } from "./hooks.ts";

/** Components take semantics only: no colours, fonts, sizes or margins can be passed. */
type Kids = { children?: ComponentChildren };
export type Tint = "accent" | "blue" | "green" | "orange" | "pink" | "purple" | "red" | "teal" | "yellow" | "gray";

const cx = (...names: (string | false | undefined)[]) => names.filter(Boolean).join(" ");

// ---- Icon ---------------------------------------------------------------------------------

/** An SF Symbol, drawn by the host as a template image and tinted with the text colour. */
export function Icon({ symbol }: { symbol: string }) {
  return <i class="icon-glyph" style={{ "--glyph": `url(wisp://app/__symbol/${encodeURIComponent(symbol)}.png)` } as never} />;
}

// ---- Window and layout --------------------------------------------------------------------

/** The window and its layout: the first child is the sidebar, the last the detail, a third in between is the content list.
 *  `sidebar` is declared by the page; the native toolbar's sidebar item toggles it. */
export function Window({ title, subtitle, columns, sidebar = true, children }: {
  title: string; subtitle?: string; columns: 2 | 3; sidebar?: boolean;
} & Kids) {
  useEffect(() => setWindowTitle(title, subtitle), [title, subtitle]);
  return <div class={cx("window", "native", columns === 2 && "two", !sidebar && "sidebar-hidden")}>{children}</div>;
}

/** A content column. The native toolbar owns the titlebar, so columns are only content containers. */
const Column = ({ kind, children }: { kind: string } & Kids) => (
  <section class={cx("column", kind)}>{children}</section>
);

export const Sidebar = (p: Kids) => <Column kind="sidebar" {...p} />;
export const Content = (p: Kids) => <Column kind="content" {...p} />;
export const Detail = (p: Kids) => <Column kind="detail" {...p} />;

export function Search({ value, placeholder, onInput }: { value: string; placeholder?: string; onInput: (text: string) => void }) {
  return (
    <label class="search">
      <Icon symbol="magnifyingglass" />
      <input type="search" value={value} placeholder={placeholder} onInput={(e) => onInput(e.currentTarget.value)} />
    </label>
  );
}

/** Message input: Enter sends, Shift+Enter inserts a newline; sending clears the field. `busy` turns the
 *  send button into stop (the app decides what stopping means). */
export function Composer({ value, placeholder, onChange, onSend, busy, onStop, sendWith = "return", children }: {
  value: string; placeholder?: string; onChange: (text: string) => void; onSend: () => void;
  busy?: boolean; onStop?: () => void; sendWith?: "return" | "cmd+return"; children?: ComponentChildren;
}) {
  const submit = () => {
    if (busy || !value.trim()) return;
    onSend();
    onChange("");
  };
  return (
    <div class="composer">
      <textarea
        class="composer-input"
        rows={1}
        value={value}
        placeholder={placeholder}
        onInput={(e) => onChange(e.currentTarget.value)}
        onKeyDown={(e) => {
          if (e.key !== "Enter" || e.isComposing || e.shiftKey) return;
          if (sendWith === "return" ? e.metaKey : !e.metaKey) return;
          e.preventDefault();
          submit();
        }}
      />
      <div class="composer-bar">
        <Button symbol="plus" help="附件（M3）" disabled />
        <span class="spacer" />
        {children}
        <Button
          symbol={busy ? "stop.fill" : "arrow.up"}
          prominent
          disabled={!busy && !value.trim()}
          help={busy ? "停止生成" : "发送"}
          onAction={busy ? onStop ?? (() => {}) : submit}
        />
      </div>
    </div>
  );
}

// ---- Controls -----------------------------------------------------------------------------

export function Button({ title, symbol, role, prominent, disabled, help, onAction }: {
  title?: string; symbol?: string; role?: "destructive"; prominent?: boolean; disabled?: boolean; help?: string; onAction?: () => void;
}) {
  return (
    <button class={cx("btn", prominent && "prominent", role === "destructive" && "destructive", !title && "icon")} disabled={disabled} title={help} onClick={onAction}>
      {symbol && <Icon symbol={symbol} />}
      {title}
    </button>
  );
}

export function Menu({ title, symbol, children }: { title?: string; symbol?: string } & Kids) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const away = (e: Event) => !root.current?.contains(e.target as Node) && setOpen(false);
    document.addEventListener("mousedown", away);
    return () => document.removeEventListener("mousedown", away);
  }, [open]);
  return (
    <div class="menu" ref={root} onClick={() => open && setOpen(false)}>
      <button class={cx("btn", !title && "icon")} onClick={(e) => { e.stopPropagation(); setOpen(!open); }}>
        {symbol && <Icon symbol={symbol} />}
        {title}
      </button>
      {open && <div class="menu-pop">{children}</div>}
    </div>
  );
}

export interface ContextMenuItem {
  id: string;
  title: string;
  onAction: () => void;
  destructive?: boolean;
  disabled?: boolean;
}

/** Right-click menu: the host shows a native NSMenu at the pointer and returns only the selected id. */
export function ContextMenu({ items, children }: { items: ContextMenuItem[] } & Kids) {
  return (
    <div
      class="context"
      onContextMenu={(e) => {
        e.preventDefault();
        showContextMenu(
          items.map(({ id, title, destructive, disabled }) => ({ id, title, destructive, disabled })),
          (id) => items.find((item) => item.id === id)?.onAction(),
        );
      }}
    >
      {children}
    </div>
  );
}

export const Divider = () => <hr class="divider" />;
export const Spacer = () => <span class="spacer" />;

export function Text({ children, style, selectable }: { style?: "title" | "headline" | "body" | "caption" | "secondary"; selectable?: boolean } & Kids) {
  return <p class={cx("text", style)} data-selectable={selectable ? "" : undefined}>{children}</p>;
}

export function Stack({ axis, spacing = "regular", children }: { axis?: "vertical" | "horizontal"; spacing?: "tight" | "regular" | "loose" } & Kids) {
  return <div class={cx("stack", axis === "horizontal" && "horizontal", spacing)}>{children}</div>;
}

export function Empty({ title, symbol, description }: { title: string; symbol?: string; description?: string }) {
  return (
    <div class="empty">
      {symbol && <Icon symbol={symbol} />}
      <p class="text headline">{title}</p>
      {description && <p class="text">{description}</p>}
    </div>
  );
}

/** A scrolling region; `anchor="bottom"` keeps the newest content in view (chat transcripts). */
export function Scroll({ anchor, children }: { anchor?: "bottom" } & Kids) {
  const ref = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    if (anchor === "bottom") ref.current?.scrollTo({ top: ref.current.scrollHeight });
  });
  return <div class="scroll" ref={ref} data-anchor={anchor}>{children}</div>;
}

// ---- Markdown -----------------------------------------------------------------------------

/** Inline marks for now: `code`. Everything else is plain text. */
function inline(text: string): ComponentChildren[] {
  return text
    .split(/(`[^`]*`)/g)
    .filter(Boolean)
    .map((part, index) =>
      part.length > 1 && part.startsWith("`") && part.endsWith("`")
        ? <code key={index}>{part.slice(1, -1)}</code>
        : part
    );
}

const breakPattern = /^(#{1,6}\s|```|>\s?|\s*[-*]\s+|\s*\d+\.\s+)/;

function parseBlocks(text: string): ComponentChildren[] {
  const lines = text.split("\n");
  const blocks: ComponentChildren[] = [];
  let index = 0;
  while (index < lines.length) {
    const line = lines[index] ?? "";
    const fence = line.match(/^```(\w*)/);
    if (fence) {
      const code: string[] = [];
      index++;
      while (index < lines.length && !/^```/.test(lines[index] ?? "")) {
        code.push(lines[index] ?? "");
        index++;
      }
      index++;
      blocks.push(<pre key={blocks.length}><code>{code.join("\n")}</code></pre>);
      continue;
    }
    const heading = line.match(/^(#{1,6})\s+(.*)$/);
    if (heading) {
      const level = (heading[1] ?? "#").length;
      const Tag = `h${level}` as "h1" | "h2" | "h3" | "h4" | "h5" | "h6";
      blocks.push(<Tag key={blocks.length}>{inline(heading[2] ?? "")}</Tag>);
      index++;
      continue;
    }
    if (/^>\s?/.test(line)) {
      const quote: string[] = [];
      while (index < lines.length && /^>\s?/.test(lines[index] ?? "")) {
        quote.push((lines[index] ?? "").replace(/^>\s?/, ""));
        index++;
      }
      blocks.push(<blockquote key={blocks.length}>{inline(quote.join(" "))}</blockquote>);
      continue;
    }
    if (/^\s*[-*]\s+/.test(line)) {
      const items: string[] = [];
      while (index < lines.length && /^\s*[-*]\s+/.test(lines[index] ?? "")) {
        items.push((lines[index] ?? "").replace(/^\s*[-*]\s+/, ""));
        index++;
      }
      blocks.push(<ul key={blocks.length}>{items.map((item, i) => <li key={i}>{inline(item)}</li>)}</ul>);
      continue;
    }
    if (/^\s*\d+\.\s+/.test(line)) {
      const items: string[] = [];
      while (index < lines.length && /^\s*\d+\.\s+/.test(lines[index] ?? "")) {
        items.push((lines[index] ?? "").replace(/^\s*\d+\.\s+/, ""));
        index++;
      }
      blocks.push(<ol key={blocks.length}>{items.map((item, i) => <li key={i}>{inline(item)}</li>)}</ol>);
      continue;
    }
    if (line.trim() === "") {
      index++;
      continue;
    }
    const paragraph: string[] = [];
    while (index < lines.length && (lines[index] ?? "").trim() !== "" && !breakPattern.test(lines[index] ?? "")) {
      paragraph.push(lines[index] ?? "");
      index++;
    }
    blocks.push(<p key={blocks.length}>{inline(paragraph.join(" "))}</p>);
  }
  return blocks;
}

/** Message body: paragraphs, headings, lists, fenced code, inline code and quotes. Tables come later. */
export function Markdown({ text }: { text: string }) {
  return <div class="markdown" data-selectable>{parseBlocks(text)}</div>;
}

// ---- Lists --------------------------------------------------------------------------------

/** Arrow keys move the selection while the list has focus. */
export function List({ selection, onSelect, children }: { selection?: string | null; onSelect?: (value: string) => void } & Kids) {
  const ref = useRef<HTMLDivElement>(null);
  const move = (e: KeyboardEvent) => {
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
    const rows = [...(ref.current?.querySelectorAll<HTMLElement>("[data-value]") ?? [])];
    const at = rows.findIndex((r) => r.dataset.value === selection);
    const next = rows[Math.max(0, Math.min(rows.length - 1, at + (e.key === "ArrowDown" ? 1 : -1)))];
    if (next?.dataset.value) onSelect?.(next.dataset.value);
    next?.scrollIntoView({ block: "nearest" });
    e.preventDefault();
  };
  return (
    <div class="scroll list" ref={ref} tabIndex={0} onKeyDown={move} onClick={(e) => {
      const row = (e.target as HTMLElement).closest<HTMLElement>("[data-value]");
      if (row?.dataset.value) onSelect?.(row.dataset.value);
    }} data-selection={selection ?? ""}>
      {children}
    </div>
  );
}

/** A titled group in a list, or a rounded group in a settings pane. */
export const Section = ({ title, children }: { title?: string } & Kids) => (
  <div class="section">
    {title && <div class="section-title">{title}</div>}
    <div class="section-body">{children}</div>
  </div>
);

export function Row({ value, title, subtitle, symbol, badge, selected }: {
  value: string; title: string; subtitle?: string; symbol?: string; badge?: string | number; selected?: boolean;
}) {
  return (
    <div class={cx("row", selected && "selected")} data-value={value}>
      {symbol && <Icon symbol={symbol} />}
      <span class="label">
        <span>{title}</span>
        {subtitle && <span class="sub">{subtitle}</span>}
      </span>
      {badge !== undefined && <span class="badge">{badge}</span>}
    </div>
  );
}

export const SidebarTiles = ({ children }: Kids) => <div class="tiles">{children}</div>;

export function Tile({ title, symbol, count, tint = "accent", selected, onAction }: {
  title: string; symbol: string; count?: number; tint?: Tint; selected?: boolean; onAction?: () => void;
}) {
  return (
    <button class={cx("tile", selected && "selected")} aria-pressed={selected} onClick={onAction}>
      <span class="top">
        <span class={cx("tile-icon", `tint-${tint}`)}><Icon symbol={symbol} /></span>
        {count !== undefined && <span class="count">{count}</span>}
      </span>
      <span class="name">{title}</span>
    </button>
  );
}

// ---- Settings -----------------------------------------------------------------------------

/** The settings window page: panes become toolbar-style tabs, and the window follows the content height. */
export function Settings({ children }: { children: VNode<{ id: string; title: string; symbol: string }> | VNode<{ id: string; title: string; symbol: string }>[] }) {
  const panes = ([] as VNode<{ id: string; title: string; symbol: string }>[]).concat(children);
  const [active, setActive] = useState(panes[0]?.props.id);
  const body = useRef<HTMLDivElement>(null);
  const current = panes.find((p) => p.props.id === active) ?? panes[0];
  useTabs(
    panes.map((p) => ({ id: p.props.id, title: p.props.title, symbol: p.props.symbol, selected: p.props.id === current?.props.id })),
    setActive,
  );
  useEffect(() => setWindowTitle(current?.props.title ?? boot.title), [current?.props.title]);
  useLayoutEffect(() => {
    const el = body.current;
    if (!el) return;
    const report = () => setContentHeight(el.getBoundingClientRect().height);
    report();
    const watcher = new ResizeObserver(report);
    watcher.observe(el);
    return () => watcher.disconnect();
  }, [active]);
  return <div ref={body}>{current}</div>;
}

/** One settings tab; `Settings` reads its props and shows the selected pane's children. */
export const Pane = ({ children }: { id: string; title: string; symbol: string } & Kids) => <div class="pane">{children}</div>;

const Field = ({ title, children }: { title: string } & Kids) => (
  <div class="field">
    <label>{title}</label>
    {children}
  </div>
);

export const Toggle = ({ title, value, onChange }: { title: string; value: boolean; onChange: (v: boolean) => void }) => (
  <Field title={title}><input class="switch" type="checkbox" checked={value} onChange={(e) => onChange(e.currentTarget.checked)} /></Field>
);
export const TextField = ({ title, value, placeholder, onChange }: {
  title: string; value: string; placeholder?: string; onChange: (v: string) => void;
}) => (
  <Field title={title}><input type="text" value={value} placeholder={placeholder} onInput={(e) => onChange(e.currentTarget.value)} /></Field>
);
export const SecureField = ({ title, value, placeholder, onChange }: {
  title: string; value?: string; placeholder?: string; onChange: (v: string) => void;
}) => (
  <Field title={title}><input type="password" value={value ?? ""} placeholder={placeholder} onInput={(e) => onChange(e.currentTarget.value)} /></Field>
);
export const Picker = ({ title, value, options, onChange }: { title: string; value: string; options: { value: string; title: string }[]; onChange: (v: string) => void }) => (
  <Field title={title}>
    <select value={value} onChange={(e) => onChange(e.currentTarget.value)}>
      {options.map((o) => <option key={o.value} value={o.value}>{o.title}</option>)}
    </select>
  </Field>
);

export { openSettings };

/** Renders the app into the page; the settings window loads the same bundle and shows `settings` instead. */
export function run(app: VNode, settings?: VNode): void {
  document.body.dataset.window = boot.window;
  mount(boot.window === "settings" && settings ? settings : app, document.body);
}
