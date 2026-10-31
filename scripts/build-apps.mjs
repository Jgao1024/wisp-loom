// Builds every apps/<name>/ into build/apps/<name>/: manifest.json, ui.js and the backend.
// Usage: node scripts/build-apps.mjs [--watch]   (--watch only keeps ui.js rebuilding; used by `make dev`)
import { build, context } from "esbuild";
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync } from "node:fs";
import { basename } from "node:path";

const watch = process.argv.includes("--watch");
const names = readdirSync("apps").filter((name) => existsSync(`apps/${name}/manifest.json`));

for (const name of names) {
  const source = `apps/${name}`;
  const out = `build/apps/${name}`;
  const manifest = JSON.parse(readFileSync(`${source}/manifest.json`, "utf8"));
  mkdirSync(out, { recursive: true });
  cpSync(`${source}/manifest.json`, `${out}/manifest.json`);

  const options = {
    entryPoints: [`${source}/ui/main.tsx`],
    outfile: `${out}/${manifest.ui}`,
    bundle: true,
    format: "iife",
    target: "es2022",
    jsx: "automatic",
    jsxImportSource: "preact",
    minify: !watch,
    logLevel: "warning",
  };
  if (watch) await (await context(options)).watch();
  else await build(options);

  if (!manifest.backend || watch) continue;
  mkdirSync(`${out}/backend`, { recursive: true });
  if (existsSync(`${source}/backend/Cargo.toml`)) {
    // The target dir comes from .cargo/config.toml.
    execFileSync("cargo", ["build", "--release", "--manifest-path", `${source}/backend/Cargo.toml`], {
      stdio: "inherit",
    });
    const binary = basename(manifest.backend.exec[0]);
    cpSync(`build/cargo/release/${binary}`, `${out}/backend/${binary}`);
  } else {
    cpSync(`${source}/backend`, `${out}/backend`, { recursive: true });
  }
}
