import "@wisp/ui/style.css";
import {
  Button, Content, Detail, Divider, Empty, List, Menu, Pane, Picker, Row, SecureField, Section, Settings, Sidebar,
  SidebarTiles, Stack, Text, TextField, Tile, Toggle, ToolbarGroup, Window, Search, call, run, setSecret, usePersisted,
  useCommands, useMemo, useState, useStream,
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
  const [showGroups] = usePersisted("showGroups", true);
  const [name] = usePersisted("name", "Sample");
  const [items, setItems] = useState(initial);
  const [group, setGroup] = useState<Item["group"] | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [ascending, setAscending] = useState(true);
  const [query, setQuery] = useState("");
  const reply = useStream();
  const [running, setRunning] = useState<{ abort(): void } | null>(null);

  const shown = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const list = items.filter((item) => (!group || item.group === group) && item.title.toLowerCase().includes(needle));
    return list.sort((a, b) => a.title.localeCompare(b.title) * (ascending ? 1 : -1));
  }, [items, group, query, ascending]);
  const current = items.find((item) => item.id === selected);
  const count = (g: Item["group"]) => items.filter((i) => i.group === g).length;

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

  useCommands([{ id: "new", menu: "file", title: "New Item", shortcut: "cmd+n", run: add }]);

  return (
    <Window title={name || "Sample"} columns={3}>
      <Sidebar>
        <SidebarTiles>
          <Tile title="All" symbol="tray.full" tint="blue" count={items.length} selected={group === null} onAction={() => setGroup(null)} />
          <Tile title="Inbox" symbol="tray" tint="orange" count={count("Inbox")} selected={group === "Inbox"} onAction={() => setGroup("Inbox")} />
        </SidebarTiles>
        <List selection={group} onSelect={(value) => setGroup(value as Item["group"])}>
          <Section title="Groups">
            <Row value="Inbox" title="Inbox" symbol="tray" badge={count("Inbox")} selected={group === "Inbox"} />
            <Row value="Archive" title="Archive" symbol="archivebox" badge={count("Archive")} selected={group === "Archive"} />
          </Section>
        </List>
      </Sidebar>
      <Content
        title={group ?? "All"}
        subtitle={`${shown.length} items`}
        toolbar={
          <ToolbarGroup>
            <Menu symbol="arrow.up.arrow.down">
              <Button title="Title A–Z" onAction={() => setAscending(true)} />
              <Button title="Title Z–A" onAction={() => setAscending(false)} />
            </Menu>
            <Button symbol="plus" help="New item" onAction={add} />
          </ToolbarGroup>
        }
      >
        <List selection={selected} onSelect={setSelected}>
          {shown.map((item) => (
            <Row key={item.id} value={item.id} title={item.title} subtitle={showGroups ? item.group : undefined} selected={item.id === selected} />
          ))}
        </List>
      </Content>
      <Detail toolbar={<Search value={query} placeholder="Search" onInput={setQuery} />}>
        {current ? (
          <div class="pad">
            <Stack>
              <Text style="title">{current.title}</Text>
              <Text style="secondary">{current.group}</Text>
              <Divider />
              <Stack axis="horizontal">
                <Button title="Echo via backend" prominent onAction={echo} />
                {running && <Button title="Stop" onAction={() => running.abort()} />}
              </Stack>
              <Text selectable>{reply.text}</Text>
            </Stack>
          </div>
        ) : (
          <Empty title="No Selection" symbol="doc.text" description="Select an item to see its details." />
        )}
      </Detail>
    </Window>
  );
}

function SampleSettings() {
  const [showGroups, setShowGroups] = usePersisted("showGroups", true);
  const [name, setName] = usePersisted("name", "Sample");
  const [sort, setSort] = usePersisted("sort", "title");
  const [apiKey, setApiKey] = useState("");
  return (
    <Settings>
      <Pane id="general" title="General" symbol="gearshape">
        <Section title="Window">
          <TextField title="Title" value={name} onChange={setName} />
          <Toggle title="Show group under each item" value={showGroups} onChange={setShowGroups} />
          <Picker title="Sort by" value={sort} onChange={setSort} options={[{ value: "title", title: "Title" }, { value: "group", title: "Group" }]} />
        </Section>
      </Pane>
      <Pane id="account" title="Account" symbol="key">
        <Section title="Backend">
          <SecureField title="API key" placeholder="sk-…" value={apiKey} onChange={(v) => { setApiKey(v); void setSecret("apiKey", v); }} />
        </Section>
      </Pane>
    </Settings>
  );
}

run(<Sample />, <SampleSettings />);
