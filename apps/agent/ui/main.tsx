import "@wisp/ui/style.css";
import {
  Button, Composer, ContextMenu, Detail, Empty, Icon, List, Markdown, Menu, Pane, Picker, Row, Scroll, Search, Section,
  SecureField, Settings, Sidebar, Stack, Text, TextField, Toggle, Window, run, useCommands, useEffect, useMemo, usePersisted,
  useRef, useState, useStream,
} from "@wisp/ui";
import { agents, initialConversations, models, streamingReply, type Conversation, type Message } from "./mock.ts";

const groups = [
  { id: "today", title: "今天" },
  { id: "yesterday", title: "昨天" },
] as const;

const titleFrom = (text: string) => (text.length > 18 ? `${text.slice(0, 18)}…` : text);

function MessageView({ message }: { message: Message }) {
  return message.role === "user" ? (
    <div class="message user">
      <div class="bubble" data-selectable>{message.text}</div>
    </div>
  ) : (
    <div class="message assistant">
      <Markdown text={message.text} />
    </div>
  );
}

function Agent() {
  const [defaultAgent] = usePersisted("defaultAgent", "Wisp Agent");
  const [defaultModel] = usePersisted("defaultModel", "GPT-5");
  const [autoTitle] = usePersisted("autoTitle", true);
  const [sendKey] = usePersisted("sendKey", "return");
  const [conversations, setConversations] = useState<Conversation[]>(initialConversations);
  const [activeId, setActiveId] = useState<string | null>(initialConversations[0]?.id ?? null);
  const [query, setQuery] = useState("");
  const [text, setText] = useState("");
  const [busyId, setBusyId] = useState<string | null>(null);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [draft, setDraft] = useState("");
  const stream = useStream();
  const timer = useRef<number | null>(null);
  const output = useRef("");

  const active = conversations.find((conversation) => conversation.id === activeId);
  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return conversations.filter((conversation) => conversation.title.toLowerCase().includes(needle));
  }, [conversations, query]);
  const streamingHere = busyId !== null && busyId === active?.id;
  const hasMessages = (active?.messages.length ?? 0) > 0 || streamingHere;

  useEffect(() => () => {
    if (timer.current !== null) window.clearTimeout(timer.current);
  }, []);

  const commitReply = (conversationId: string, body: string) => {
    if (timer.current !== null) window.clearTimeout(timer.current);
    timer.current = null;
    if (body) {
      const message: Message = { id: `m${Date.now()}a`, role: "assistant", text: body };
      setConversations((list) =>
        list.map((conversation) =>
          conversation.id === conversationId
            ? { ...conversation, messages: [...conversation.messages, message] }
            : conversation
        )
      );
    }
    output.current = "";
    setBusyId(null);
    stream.set("");
  };

  const send = () => {
    const body = text.trim();
    if (!body || !active || busyId) return;
    const conversationId = active.id;
    const message: Message = { id: `m${Date.now()}`, role: "user", text: body };
    setConversations((list) =>
      list.map((conversation) =>
        conversation.id === conversationId
          ? {
              ...conversation,
              title: conversation.messages.length === 0 && autoTitle ? titleFrom(body) : conversation.title,
              messages: [...conversation.messages, message],
            }
          : conversation
      )
    );
    stream.set("");
    output.current = "";
    setBusyId(conversationId);
    let at = 0;
    const tick = () => {
      if (at >= streamingReply.length) {
        commitReply(conversationId, output.current);
        return;
      }
      const chunk = streamingReply.slice(at, at + 2);
      at += 2;
      output.current += chunk;
      stream.append(chunk);
      timer.current = window.setTimeout(tick, 22);
    };
    timer.current = window.setTimeout(tick, 250);
  };

  const stop = () => {
    if (timer.current !== null) window.clearTimeout(timer.current);
    timer.current = null;
    if (busyId && output.current) commitReply(busyId, `${output.current}\n\n> 已停止生成。`);
    else {
      output.current = "";
      setBusyId(null);
      stream.set("");
    }
  };

  const newConversation = () => {
    const id = `c${Date.now()}`;
    const conversation: Conversation = {
      id, title: "新对话", group: "today", agent: defaultAgent, model: defaultModel, messages: [],
    };
    setConversations((list) => [conversation, ...list]);
    setActiveId(id);
  };

  const removeConversation = (id: string) => {
    if (busyId === id) stop();
    const next = conversations.filter((conversation) => conversation.id !== id);
    setConversations(next);
    if (activeId === id) setActiveId(next[0]?.id ?? null);
  };

  const startRename = (conversation: Conversation) => {
    setRenamingId(conversation.id);
    setDraft(conversation.title);
  };

  const commitRename = () => {
    const id = renamingId;
    if (!id) return;
    const title = draft.trim();
    if (title) setConversations((list) => list.map((conversation) => conversation.id === id ? { ...conversation, title } : conversation));
    setRenamingId(null);
  };

  const setAgent = (agent: string) => {
    if (!activeId) return;
    setConversations((list) => list.map((conversation) => conversation.id === activeId ? { ...conversation, agent } : conversation));
  };

  const setModel = (model: string) => {
    if (!activeId) return;
    setConversations((list) => list.map((conversation) => conversation.id === activeId ? { ...conversation, model } : conversation));
  };

  const copyMarkdown = () => {
    if (!active) return;
    const markdown = active.messages
      .map((message) => message.role === "user" ? `**You**\n\n${message.text}` : message.text)
      .join("\n\n---\n\n");
    void navigator.clipboard?.writeText(markdown);
  };

  useCommands([{ id: "new", menu: "file", title: "新建对话", shortcut: "cmd+n", run: newConversation }]);

  return (
    <Window title="Agent" columns={2}>
      <Sidebar>
        <div class="sidebar-actions">
          <button class="new-chat" onClick={newConversation}>
            <Icon symbol="square.and.pencil" />
            <span>新建对话</span>
            <span class="shortcut">⌘N</span>
          </button>
        </div>
        <div class="sidebar-search">
          <Search value={query} placeholder="搜索对话" onInput={setQuery} />
        </div>
        <List selection={activeId} onSelect={setActiveId}>
          {groups.map((group) => {
            const items = filtered.filter((conversation) => conversation.group === group.id);
            if (items.length === 0) return null;
            return (
              <Section key={group.id} title={group.title}>
                {items.map((conversation) => (
                  <ContextMenu
                    key={conversation.id}
                    items={[
                      { title: "重命名", onAction: () => startRename(conversation) },
                      { title: "删除", destructive: true, onAction: () => removeConversation(conversation.id) },
                    ]}
                  >
                    {renamingId === conversation.id ? (
                      <input
                        class="rename"
                        value={draft}
                        autoFocus
                        onFocus={(event) => event.currentTarget.select()}
                        onInput={(event) => setDraft(event.currentTarget.value)}
                        onBlur={commitRename}
                        onKeyDown={(event) => {
                          if (event.key === "Enter") { event.preventDefault(); commitRename(); }
                          if (event.key === "Escape") { event.preventDefault(); setRenamingId(null); }
                        }}
                      />
                    ) : (
                      <Row
                        value={conversation.id}
                        title={conversation.title}
                        selected={conversation.id === activeId}
                      />
                    )}
                  </ContextMenu>
                ))}
              </Section>
            );
          })}
        </List>
        {filtered.length === 0 && <div class="sidebar-search"><Text style="caption">没有匹配的对话</Text></div>}
      </Sidebar>
      <Detail
        title={active?.title ?? "新对话"}
        subtitle={active ? `${active.agent} · ${active.model}` : undefined}
        toolbar={
          <>
            <Menu symbol="ellipsis">
              <Button title="重命名" onAction={() => active && startRename(active)} />
              <Button title="复制为 Markdown" onAction={copyMarkdown} />
              <Button title="删除" role="destructive" onAction={() => active && removeConversation(active.id)} />
            </Menu>
            <Menu title={active?.agent ?? "Wisp Agent"} symbol="person.crop.circle">
              {agents.map((agent) => (
                <Button key={agent} title={agent} onAction={() => setAgent(agent)} />
              ))}
            </Menu>
            <Button symbol="square.and.arrow.up" help="导出 Markdown" onAction={copyMarkdown} />
          </>
        }
      >
        {hasMessages ? (
          <Scroll anchor="bottom">
            <div class="thread">
              {active?.messages.map((message) => <MessageView key={message.id} message={message} />)}
              {streamingHere && (
                <div class="message assistant">
                  <Markdown text={`${stream.text}▍`} />
                </div>
              )}
            </div>
          </Scroll>
        ) : (
          <Empty
            title={active?.agent ?? "Wisp Agent"}
            symbol="sparkles"
            description="可以帮你读代码、写草稿、解释概念。"
          />
        )}
        <div class="composer-wrap">
          <Composer
            value={text}
            placeholder="给 Wisp Agent 发消息…"
            onChange={setText}
            onSend={send}
            busy={busyId !== null}
            onStop={stop}
            sendWith={sendKey === "cmd+return" ? "cmd+return" : "return"}
          >
            <Menu title={active?.model ?? "GPT-5"} symbol="cpu">
              {models.map((model) => (
                <Button key={model} title={model} onAction={() => setModel(model)} />
              ))}
            </Menu>
          </Composer>
        </div>
      </Detail>
    </Window>
  );
}

function AgentSettings() {
  const [agent, setAgent] = usePersisted("defaultAgent", "Wisp Agent");
  const [model, setModel] = usePersisted("defaultModel", "GPT-5");
  const [autoTitle, setAutoTitle] = usePersisted("autoTitle", true);
  const [sendKey, setSendKey] = usePersisted("sendKey", "return");
  const [protocol, setProtocol] = usePersisted("protocol", "openai-completions");
  const [baseURL, setBaseURL] = usePersisted("baseURL", "https://api.openai.com/v1");
  const [apiKey, setApiKey] = useState("");

  return (
    <Settings>
      <Pane id="general" title="通用" symbol="gearshape">
        <Section title="对话">
          <Picker title="默认 Agent" value={agent} onChange={setAgent} options={agents.map((name) => ({ value: name, title: name }))} />
          <Picker title="默认模型" value={model} onChange={setModel} options={models.map((name) => ({ value: name, title: name }))} />
          <Toggle title="自动生成标题" value={autoTitle} onChange={setAutoTitle} />
          <Picker
            title="发送键"
            value={sendKey}
            onChange={setSendKey}
            options={[{ value: "return", title: "回车" }, { value: "cmd+return", title: "⌘ 回车" }]}
          />
        </Section>
      </Pane>
      <Pane id="models" title="模型" symbol="cpu">
        <Section title="服务商">
          <Picker
            title="协议"
            value={protocol}
            onChange={setProtocol}
            options={[
              { value: "openai-completions", title: "OpenAI Chat Completions" },
              { value: "anthropic-messages", title: "Anthropic Messages" },
            ]}
          />
          <TextField title="Base URL" value={baseURL} onChange={setBaseURL} />
          <SecureField title="API Key" value={apiKey} placeholder="sk-…" onChange={setApiKey} />
        </Section>
        <Section title="模型">
          <Picker title="模型" value={model} onChange={setModel} options={models.map((name) => ({ value: name, title: name }))} />
        </Section>
        <Stack axis="horizontal">
          <Button title="测试连接" disabled help="需要后端（M1）" />
        </Stack>
      </Pane>
    </Settings>
  );
}

run(<Agent />, <AgentSettings />);
