import {
  Button, Content, Detail, Divider, Empty, List, Menu, Row, Section, Sidebar, SidebarTiles, Split, Stack, Text,
  Tile, Toolbar, ToolbarGroup, Window, call, mount, useMemo, useState, useStream,
} from "@wisp/ui";

interface Item {
  id: string;
  title: string;
  group: "Inbox" | "Archive";
}

const initial: Item[] = [
  { id: "1", title: "Write the plugin docs", group: "Inbox" },
  { id: "2", title: "Try the Rust backend", group: "Inbox" },
  { id: "3", title: "Ship milestone 0", group: "Archive" },
];

function Sample() {
  const [items, setItems] = useState(initial);
  const [group, setGroup] = useState<Item["group"] | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [ascending, setAscending] = useState(true);
  const [query, setQuery] = useState("");
  const reply = useStream();
  const [running, setRunning] = useState<{ abort(): void } | null>(null);

  const shown = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const list = items.filter(
      (item) => (!group || item.group === group) && item.title.toLowerCase().includes(needle),
    );
    return list.sort((a, b) => a.title.localeCompare(b.title) * (ascending ? 1 : -1));
  }, [items, group, query, ascending]);
  const current = items.find((item) => item.id === selected);

  const add = () => {
    const id = String(Date.now());
    setItems([...items, { id, title: `New item ${items.length + 1}`, group: group ?? "Inbox" }]);
    setSelected(id);
  };

  const echo = async () => {
    if (!current) return;
    reply.set("");
    const request = call("echo", { text: current.title }, { onEvent: (event) => reply.append(event.delta) });
    setRunning(request);
    try {
      await request;
    } catch (error) {
      reply.append(`\n[${(error as { code?: string }).code ?? "error"}]`);
    }
    setRunning(null);
  };

  return (
    <Window title="Sample">
      <Split columns={3} query={query} placeholder="Search" onQuery={setQuery}>
        <Sidebar>
          <SidebarTiles>
            <Tile title="All" symbol="tray.full" tint="blue" count={items.length} onAction={() => setGroup(null)} />
            <Tile
              title="Inbox" symbol="tray" tint="orange"
              count={items.filter((i) => i.group === "Inbox").length} onAction={() => setGroup("Inbox")}
            />
          </SidebarTiles>
          <List selection={group} onSelect={(value) => setGroup(value as Item["group"])}>
            <Section title="Groups">
              <Row value="Inbox" title="Inbox" symbol="tray" badge={items.filter((i) => i.group === "Inbox").length} />
              <Row value="Archive" title="Archive" symbol="archivebox" badge={items.filter((i) => i.group === "Archive").length} />
            </Section>
          </List>
        </Sidebar>
        <Content title={group ?? "All"} subtitle={`${shown.length} items`}>
          <Toolbar>
            <Menu symbol="arrow.up.arrow.down">
              <Button title="Title A–Z" onAction={() => setAscending(true)} />
              <Button title="Title Z–A" onAction={() => setAscending(false)} />
            </Menu>
            <ToolbarGroup>
              <Button symbol="plus" help="New item" onAction={add} />
            </ToolbarGroup>
          </Toolbar>
          <List selection={selected} onSelect={setSelected}>
            {shown.map((item) => (
              <Row key={item.id} value={item.id} title={item.title} subtitle={item.group} />
            ))}
          </List>
        </Content>
        <Detail>
          {current ? (
            <Stack spacing="regular">
              <Text style="title">{current.title}</Text>
              <Text style="secondary">{current.group}</Text>
              <Divider />
              <Stack axis="horizontal">
                <Button title="Echo via backend" prominent onAction={echo} />
                {running ? <Button title="Stop" onAction={() => running.abort()} /> : null}
              </Stack>
              <Text text={reply} selectable />
            </Stack>
          ) : (
            <Empty title="No Selection" symbol="doc.text" description="Select an item to see its details." />
          )}
        </Detail>
      </Split>
    </Window>
  );
}

mount(<Sample />);
