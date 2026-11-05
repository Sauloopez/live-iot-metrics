// Live charts of a reading (/recipe-batch/:id). Self contained:
//   1. registers a simulated node over real CoAP (inject.exs) and creates a reading of it
//      with 20 minutes of history (seed.exs)
//   2. checks the charts, hover tooltip, range status, table view, dark theme, UTC axis
//   3. sends live readings over CoAP that leave the range and checks the charts react
import { spawn, spawnSync } from "node:child_process";
import {
  BASE_URL,
  ROOT_DIR,
  checker,
  fakeMac,
  launch,
  shot,
} from "./support.mjs";

const MAC = fakeMac(4);
const t = checker("Live charts");
const { browser, page, errors } = await launch({
  viewport: { width: 1400, height: 1000 },
});

const run = (cmd, args) => {
  const result = spawnSync(cmd, args, { cwd: ROOT_DIR, encoding: "utf8" });
  if (result.status !== 0)
    throw new Error(`${cmd} ${args.join(" ")} failed: ${result.stderr}`);
  return result.stdout;
};

// The server stores CoAP readings in batches flushed every second
run("elixir", ["e2e/inject.exs", MAC, "register", "1"]);
await new Promise((r) => setTimeout(r, 2000));
const batchId = run("mix", ["run", "--no-start", "e2e/seed.exs", MAC]).match(
  /BATCH_ID=(\S+)/,
)[1];

await page.goto(`${BASE_URL}/recipe-batch/${batchId}`);
await page.waitForSelector("[phx-hook=ChartHook] canvas", { timeout: 15000 });
await page.waitForTimeout(1200);

const charts = page.locator("[phx-hook=ChartHook]");
t.check(
  "three charts rendered",
  (await charts.count()) === 3,
  `${await charts.count()} found`,
);

const chartState = () =>
  page.evaluate(() =>
    Array.from(document.querySelectorAll("[phx-hook=ChartHook]")).map((el) => {
      const canvas = el.querySelector("canvas");
      return {
        label: el.dataset.label,
        min: el.dataset.min,
        max: el.dataset.max,
        width: canvas?.width,
        height: canvas?.height,
        aria: canvas?.getAttribute("aria-label"),
      };
    }),
  );

const initial = await chartState();
for (const c of initial) {
  t.check(
    `chart ${c.label} has canvas size`,
    c.width > 0 && c.height > 0,
    `${c.width}x${c.height}`,
  );
  t.check(
    `chart ${c.label} received range`,
    c.min && c.max,
    `${c.min}–${c.max}`,
  );
  t.check(`chart ${c.label} aria summary`, /latest/.test(c.aria || ""), c.aria);
}
await shot(page, "01-initial-light");

// Hover across the temperature chart to bring up crosshair + tooltip
const temp = page.locator("[phx-hook=ChartHook][data-label=temperature]");
const tempWrapper = temp.locator(
  "xpath=ancestor::div[contains(@class,'chart-wrapper')]",
);
await temp.scrollIntoViewIfNeeded();
const box = await temp.boundingBox();
for (const f of [0.2, 0.4, 0.45, 0.5]) {
  await page.mouse.move(box.x + box.width * f, box.y + box.height * 0.5);
  await page.waitForTimeout(250);
}
await shot(tempWrapper, "02-hover-tooltip");
await page.mouse.move(0, 0);

// Live readings over real CoAP: temperature climbs past 30, humidity drops under 40
const injector = spawn(
  "elixir",
  ["e2e/inject.exs", MAC, "live", "10", "1000"],
  { cwd: ROOT_DIR, stdio: "ignore" },
);
await page.waitForTimeout(6000);
await shot(page, "03-live-midway");
await new Promise((r) => injector.on("exit", r));
await page.waitForTimeout(2500);

const status = await tempWrapper.locator("[id^=chart-status-]").innerText();
t.check(
  "temperature badge flags out of range",
  /Out of range/.test(status),
  status.trim(),
);

const humStatus = await page
  .locator("[phx-hook=ChartHook][data-label=air_humidity]")
  .locator("xpath=ancestor::div[contains(@class,'chart-wrapper')]")
  .locator("[id^=chart-status-]")
  .innerText();
t.check(
  "humidity badge flags out of range",
  /Out of range/.test(humStatus),
  humStatus.trim(),
);

const liveAria = (await chartState()).find(
  (c) => c.label === "temperature",
).aria;
t.check(
  "live readings reached the chart",
  liveAria !== initial.find((c) => c.label === "temperature").aria,
  liveAria,
);
await shot(page, "04-live-out-of-range");

// Accessible table view
await tempWrapper.locator("details summary").click();
const rows = await tempWrapper.locator("details tbody tr").count();
t.check("table view lists readings", rows > 0, `${rows} rows`);
const outRows = await tempWrapper
  .locator("details tbody tr", { hasText: "Out" })
  .count();
t.check(
  "table view marks out-of-range rows",
  outRows > 0,
  `${outRows} rows out`,
);
await shot(tempWrapper, "05-table-view");
await tempWrapper.locator("details summary").click();

// Theme switch re-themes the canvas live
const seriesColor = () =>
  page.evaluate(() =>
    getComputedStyle(document.querySelector("[phx-hook=ChartHook]"))
      .getPropertyValue("--viz-series")
      .trim(),
  );
const colorBefore = await seriesColor();
await page.evaluate(() => {
  localStorage.setItem("phx:theme", "dark");
  document.documentElement.setAttribute("data-theme", "dark");
});
await page.waitForTimeout(800);
const colorAfter = await seriesColor();
t.check(
  "dark theme swaps chart tokens",
  colorBefore !== colorAfter,
  `${colorBefore} -> ${colorAfter}`,
);
await shot(page, "06-dark");
await page.evaluate(() => {
  localStorage.removeItem("phx:theme");
  document.documentElement.setAttribute("data-theme", "light");
});

// Chart and server header agree on time zone and number format
const header = await tempWrapper.locator(".font-mono.font-bold").innerText();
await temp.hover({
  position: { x: (await temp.boundingBox()).width - 12, y: 120 },
});
await page.waitForTimeout(400);
const aria = await page.evaluate(() =>
  document
    .querySelector("[phx-hook=ChartHook][data-label=temperature] canvas")
    .getAttribute("aria-label"),
);
t.check(
  "header value uses dot decimals",
  /^\d+\.\d{2}$/.test(header.trim()),
  header.trim(),
);
t.check(
  "aria summary matches header value",
  aria.endsWith(header.trim()),
  `${aria} vs ${header.trim()}`,
);
await shot(tempWrapper, "07-utc-axis");

await t.finish(browser, errors);
