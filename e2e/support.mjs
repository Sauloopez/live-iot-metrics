// Shared helpers for the end-to-end tests (see README.md).
//
//   BASE_URL     app under test              (default http://localhost:4000)
//   CHROME_PATH  Chrome/Chromium binary      (default: Playwright's own browser)
//   HEADLESS=1   run without a window        (default: headed, so the run can be watched)
//   SLOW_MO      ms between browser actions  (default 100)
import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

export const BASE_URL = process.env.BASE_URL || "http://localhost:4000";
const E2E_DIR = dirname(fileURLToPath(import.meta.url));
export const ROOT_DIR = join(E2E_DIR, "..");
export const SHOTS_DIR = join(E2E_DIR, "shots");

// Removes data left by previous runs (cleanup.exs); every test calls it first
export function cleanup() {
  const run = spawnSync("mix", ["run", "--no-start", "e2e/cleanup.exs"], {
    cwd: ROOT_DIR,
    encoding: "utf8",
  });
  if (run.status !== 0)
    throw new Error(`cleanup failed: ${run.stderr || run.stdout}`);
  console.log(run.stdout.trim().split("\n").pop());
}

// MACs of simulated nodes start with 02:00:00:00:E2 so cleanup.exs can find their data
export const fakeMac = (n) =>
  `02:00:00:00:E2:${n.toString(16).toUpperCase().padStart(2, "0")}`;

export async function launch({
  viewport = { width: 1350, height: 1000 },
  clean = true,
} = {}) {
  if (clean) cleanup();
  const browser = await chromium.launch({
    headless: process.env.HEADLESS === "1",
    slowMo: Number(process.env.SLOW_MO ?? 100),
    executablePath: process.env.CHROME_PATH || undefined,
  });
  const page = await browser.newPage({ viewport });
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("dialog", (d) => d.accept());
  return { browser, page, errors };
}

// Saves e2e/shots/<name>.png of a page (full page) or of a single element
export function shot(target, name) {
  mkdirSync(SHOTS_DIR, { recursive: true });
  const isPage = typeof target.goto === "function";
  return target.screenshot({
    path: join(SHOTS_DIR, `${name}.png`),
    ...(isPage ? { fullPage: true } : {}),
  });
}

// Collects PASS/FAIL lines; finish() closes the browser and sets the exit code
export function checker(title) {
  const results = [];
  console.log(`\n# ${title}`);
  return {
    check(name, ok, detail = "") {
      results.push(Boolean(ok));
      console.log(
        `${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`,
      );
    },
    async finish(browser, errors = []) {
      this.check("no page errors", errors.length === 0, errors.join(" | "));
      await browser?.close();
      const failed = results.filter((ok) => !ok).length;
      console.log(`${results.length - failed}/${results.length} checks passed`);
      process.exitCode = failed ? 1 : 0;
    },
  };
}
