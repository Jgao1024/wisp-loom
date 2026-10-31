// Bundles apps/<name>/ui/main.tsx into build/apps/<name>/ui.js (one IIFE for JavaScriptCore).
// Usage: node scripts/build-ui.mjs [--watch] [app...]
import { build, context } from "esbuild";
import { existsSync, readdirSync } from "node:fs";

const args = process.argv.slice(2);
const watch = args.includes("--watch");
const names = args.filter((a) => !a.startsWith("--"));
const apps = names.length ? names : readdirSync("apps").filter((n) => existsSync(`apps/${n}/ui/main.tsx`));

for (const name of apps) {
  const options = {
    entryPoints: [`apps/${name}/ui/main.tsx`],
    outfile: `build/apps/${name}/ui.js`,
    bundle: true,
    format: "iife",
    target: "es2022",
    jsx: "automatic",
    jsxImportSource: "@wisp/ui",
    logLevel: "info",
  };
  if (watch) await (await context(options)).watch();
  else await build(options);
}
