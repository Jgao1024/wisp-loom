/** Static data for the UI skeleton: no backend, no calls. */
export type Role = "user" | "assistant";

export interface Message {
  id: string;
  role: Role;
  text: string;
}

export interface Conversation {
  id: string;
  title: string;
  group: "today" | "yesterday";
  agent: string;
  model: string;
  messages: Message[];
}

export const agents = ["Wisp Agent", "Code Reviewer"];
export const models = ["GPT-5", "Claude Sonnet 4.5", "DeepSeek V3.2"];

const statsReply = `## 统计结果

仓库里约有 18,400 行代码，\`swift/\` 和 \`ui/src/\` 占了大头。

- Swift：8,460 行（46%）
- TypeScript：5,700 行（31%）
- Rust：3,300 行（18%）
- 其他：940 行（5%）

\`\`\`bash
tokei --sort lines
\`\`\`

> 行数不含注释和空行；\`node_modules/\` 和第三方依赖没有计入。`;

const loginReply = `可以先从三处入手：

1. 把 \`redirect\` 参数统一交给 \`URLComponents\` 解析。
2. 登录成功后只保留一个 \`returnTo\` 值。
3. 失败时回到登录页，不要保留半截状态。

需要的话我可以把这段改成示例代码。`;

const streamReply = `\`useStream\` 把增量写进一个 \`ref\`，每一帧最多 \`setState\` 一次，所以快速到达的 delta 不会触发同样多次渲染。

\`\`\`ts
if (!frame.current) frame.current = requestAnimationFrame(flush);
\`\`\`

> 真正的流式后端只要按顺序调用 \`append(delta)\` 就够了。`;

const weeklyReply = `本周完成了三件事：

- 应用层拆成 \`host/\`、\`ui/\`、\`backend/\`、\`apps/\`
- 新增 \`WISP_OPEN\` 开发期启动开关与截图脚本
- 示例应用按系统三栏布局对齐

下周计划：

1. Agent 界面接上真实数据。
2. 补齐 SSO 的失败回跳。`;

export const initialConversations: Conversation[] = [
  {
    id: "c1",
    title: "统计代码量",
    group: "today",
    agent: "Wisp Agent",
    model: "GPT-5",
    messages: [
      { id: "c1m1", role: "user", text: "帮我统计这个仓库的代码量，并按语言列出占比。" },
      { id: "c1m2", role: "assistant", text: statsReply },
    ],
  },
  {
    id: "c2",
    title: "重构登录流程",
    group: "today",
    agent: "Wisp Agent",
    model: "GPT-5",
    messages: [
      { id: "c2m1", role: "user", text: "登录页的跳转逻辑有点乱，给个重构建议。" },
      { id: "c2m2", role: "assistant", text: loginReply },
    ],
  },
  {
    id: "c3",
    title: "解释 useStream 的实现",
    group: "yesterday",
    agent: "Wisp Agent",
    model: "Claude Sonnet 4.5",
    messages: [
      { id: "c3m1", role: "user", text: "`useStream` 是怎么做到每帧只渲染一次的？" },
      { id: "c3m2", role: "assistant", text: streamReply },
    ],
  },
  {
    id: "c4",
    title: "周报草稿",
    group: "yesterday",
    agent: "Wisp Agent",
    model: "DeepSeek V3.2",
    messages: [
      { id: "c4m1", role: "user", text: "把这周的改动整理成周报。" },
      { id: "c4m2", role: "assistant", text: weeklyReply },
    ],
  },
];

export const streamingReply = `## 我的建议

可以先把问题拆成两层：

1. 页面只负责把增量交给 \`useStream\`，每帧最多渲染一次。
2. 后端只负责按顺序发 \`text_delta\`，不要做布局相关的事情。

\`\`\`ts
stream.append(delta);
\`\`\`

> 这样流式输出时列表不会抖动，取消也能立刻生效。`;
