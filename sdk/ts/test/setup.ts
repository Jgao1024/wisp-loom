/** Stands in for WKWebView: records what the page posts and lets tests answer. */
const sent: any[] = [];
const g = globalThis as any;
g.window = g;
g.__wisp_boot = { appID: "t", lang: "en", title: "T", hasBackend: true, window: "main" };
g.webkit = { messageHandlers: { wisp: { postMessage: (json: string) => sent.push(JSON.parse(json)) } } };

export const posted = sent;
export const answer = (...replies: object[]) => g.__wisp_recv(replies);
export const take = () => sent.splice(0);
