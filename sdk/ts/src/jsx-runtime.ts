import type { Child, Component, Key, Props, VNode } from "./types.ts";

export declare namespace JSX {
  type Element = VNode;
  type ElementType = Component;
  interface ElementChildrenAttribute {
    children: {};
  }
  interface IntrinsicAttributes {
    key?: Key;
  }
  interface IntrinsicElements {}
}

export function jsx(type: Component, props: Props, key?: Key): VNode {
  const hostType = type.hostType;
  if (hostType === undefined) return { type, props, key };
  if (hostType === "Text" && props.children !== undefined) {
    // <Text>{n} items</Text> is sugar for <Text text="3 items" />
    const { children, ...rest } = props;
    return { type: hostType, props: { ...rest, text: textOf(children) }, key };
  }
  return { type: hostType, props, key };
}

export const jsxs = jsx;

export function Fragment(props: { children?: Child }): Child {
  return props.children;
}

function textOf(child: unknown): string {
  if (Array.isArray(child)) return child.map(textOf).join("");
  return child === null || child === undefined || typeof child === "boolean" ? "" : String(child);
}
