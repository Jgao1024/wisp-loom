import type { Stream } from "./stream.ts";
import type { Child, Component } from "./types.ts";

/** Components render as shell-native controls; they carry semantics only, never colors, fonts or sizes. */
function host<P>(type: string): Component<P> {
  const component = (() => null) as Component<P>;
  component.hostType = type;
  return component;
}

export type Tint = "accent" | "blue" | "green" | "orange" | "pink" | "purple" | "red" | "teal" | "yellow" | "gray";
type Kids = { children?: Child };

export const App = host<Kids>("App");
export const Window = host<{ title: string; subtitle?: string } & Kids>("Window");
export const Split = host<
  { columns: 2 | 3; query?: string; placeholder?: string; onQuery?: (text: string) => void } & Kids
>("Split");
export const Sidebar = host<Kids>("Sidebar");
export const Content = host<{ title?: string; subtitle?: string } & Kids>("Content");
export const Detail = host<{ title?: string } & Kids>("Detail");

export const Toolbar = host<Kids>("Toolbar");
export const ToolbarGroup = host<{ placement?: "principal" | "primaryAction" } & Kids>("ToolbarGroup");
export const ToolbarSpacer = host<{}>("ToolbarSpacer");

export const Button = host<{
  title?: string;
  symbol?: string;
  role?: "destructive" | "cancel";
  prominent?: boolean;
  shortcut?: string;
  disabled?: boolean;
  help?: string;
  onAction: () => void;
}>("Button");
export const Menu = host<{ title?: string; symbol?: string } & Kids>("Menu");
/** Menu bar entry; `shortcut` reads like "cmd+n". */
export const Command = host<{
  menu: "file" | "view";
  title: string;
  shortcut?: string;
  disabled?: boolean;
  onAction: () => void;
}>("Command");

export const List = host<{ selection?: string | null; onSelect?: (value: string) => void } & Kids>("List");
export const Section = host<{ title?: string } & Kids>("Section");
export const Row = host<{ value?: string; title: string; subtitle?: string; symbol?: string; badge?: string | number }>(
  "Row",
);
export const SidebarTiles = host<Kids>("SidebarTiles");
export const Tile = host<{ title: string; symbol: string; count?: number; tint?: Tint; onAction?: () => void }>("Tile");

export const Text = host<{
  text?: string | Stream;
  style?: "title" | "headline" | "body" | "caption" | "secondary";
  selectable?: boolean;
  children?: Child;
}>("Text");
export const Empty = host<{ title: string; symbol?: string; description?: string }>("Empty");
export const Stack = host<{ axis?: "vertical" | "horizontal"; spacing?: "tight" | "regular" | "loose" } & Kids>("Stack");
export const Spacer = host<{}>("Spacer");
export const Divider = host<{}>("Divider");

export const Settings = host<Kids>("Settings");
export const Pane = host<{ id: string; title: string; symbol: string } & Kids>("Pane");
export const TextField = host<{ title: string; value: string; onChange: (value: string) => void }>("TextField");
export const SecureField = host<{ title: string; value?: string; onChange: (value: string) => void }>("SecureField");
export const Toggle = host<{ title: string; value: boolean; onChange: (value: boolean) => void }>("Toggle");
export const Picker = host<{
  title: string;
  value: string;
  options: { value: string; title: string }[];
  onChange: (value: string) => void;
}>("Picker");
