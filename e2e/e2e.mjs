// Headed end-to-end check of the live charts on the recipe batch page.
// Usage: node e2e.mjs <batch_id> <mac>

import { spawn } from "node:child_process";

const { firefox, chromium } = require("playwright");

const [batchId, mac] = process.argv.slice(2);
const out = "/tmp/livemetrics-e2e/shots";
const results = [];
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(
    `${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`,
  );
};

let browser;
try {
  browser = await firefox.launch({ headless: false, slowMo: 150 });
} catch (e) {
  console.log(
    "firefox unavailable, falling back to system Chrome:",
    e.message.split("\n")[0],
  );
  browser = await chromium.launch({
    headless: false,
    slowMo: 150,
    executablePath: "/opt/google/chrome-canary/google-chrome-canary",
  });
}

const page = await browser.newPage({ viewport: { width: 1400, height: 1000 } });
const consoleErrors = [];
page.on("console", (m) => m.type() === "error" && consoleErrors.push(m.text()));
page.on("pageerror", (e) => consoleErrors.push(e.message));

await page.goto(`http://localhost:4000/recipe-batch/${batchId}`);
await page.waitForSelector("[phx-hook=ChartHook] canvas", { timeout: 15000 });
await page.waitForTimeout(1200);

const charts = page.locator("[phx-hook=ChartHook]");
check(
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
  check(
    `chart ${c.label} has canvas size`,
    c.width > 0 && c.height > 0,
    `${c.width}x${c.height}`,
  );
  check(`chart ${c.label} received range`, c.min && c.max, `${c.min}–${c.max}`);
  check(`chart ${c.label} aria summary`, /latest/.test(c.aria || ""), c.aria);
}
await page.screenshot({ path: `${out}/01-initial-light.png`, fullPage: true });

// Hover across the temperature chart to bring up crosshair + tooltip
const temp = page.locator("[phx-hook=ChartHook][data-label=temperature]");
await temp.scrollIntoViewIfNeeded();
const box = await temp.boundingBox();
for (const f of [0.2, 0.4, 0.45, 0.5]) {
  await page.mouse.move(box.x + box.width * f, box.y + box.height * 0.5);
  await page.waitForTimeout(250);
}
await temp
  .locator("xpath=ancestor::div[contains(@class,'chart-wrapper')]")
  .screenshot({ path: `${out}/02-hover-tooltip.png` });
await page.mouse.move(0, 0);

// Live readings over real CoAP: temperature climbs past 30, humidity drops under 40
const pointsBefore = await page.evaluate(() => {
  const el = document.querySelector(
    "[phx-hook=ChartHook][data-label=temperature]",
  );
  return JSON.parse(el.dataset.readings).length;
});
const injector = spawn(
  "elixir",
  ["/tmp/livemetrics-e2e/inject.exs", mac, "live", "10", "1000"],
  {
    stdio: "inherit",
  },
);
await page.waitForTimeout(6000);
await page.screenshot({ path: `${out}/03-live-midway.png`, fullPage: true });
await new Promise((r) => injector.on("exit", r));
await page.waitForTimeout(2500);

const tempWrapper = temp.locator(
  "xpath=ancestor::div[contains(@class,'chart-wrapper')]",
);
const status = await tempWrapper.locator("[id^=chart-status-]").innerText();
check(
  "temperature badge flags out of range",
  /Out of range/.test(status),
  status.trim(),
);

const humStatus = await page
  .locator("[phx-hook=ChartHook][data-label=air_humidity]")
  .locator("xpath=ancestor::div[contains(@class,'chart-wrapper')]")
  .locator("[id^=chart-status-]")
  .innerText();
check(
  "humidity badge flags out of range",
  /Out of range/.test(humStatus),
  humStatus.trim(),
);

const liveAria = (await chartState()).find(
  (c) => c.label === "temperature",
).aria;
check(
  "live readings reached the chart",
  liveAria !== initial.find((c) => c.label === "temperature").aria,
  liveAria,
);

await page.screenshot({
  path: `${out}/04-live-out-of-range.png`,
  fullPage: true,
});

// Accessible table view
await tempWrapper.locator("details summary").click();
const rows = await tempWrapper.locator("details tbody tr").count();
check("table view lists readings", rows > 0, `${rows} rows`);
const outRows = await tempWrapper
  .locator("details tbody tr", { hasText: "Out" })
  .count();
check("table view marks out-of-range rows", outRows > 0, `${outRows} rows out`);
await tempWrapper.screenshot({ path: `${out}/05-table-view.png` });
await tempWrapper.locator("details summary").click();

// Theme switch re-themes the canvas live
const pixel = () =>
  page.evaluate(() => {
    const c = document.querySelector(
      "[phx-hook=ChartHook][data-label=light] canvas",
    );
    const ctx = c.getContext("2d");
    return Array.from(ctx.getImageData(5, 5, 1, 1).data).join(",");
  });
const tickColorBefore = await page.evaluate(() => {
  const el = document.querySelector("[phx-hook=ChartHook]");
  return getComputedStyle(el).getPropertyValue("--viz-series").trim();
});
await page.evaluate(() => {
  localStorage.setItem("phx:theme", "dark");
  document.documentElement.setAttribute("data-theme", "dark");
});
await page.waitForTimeout(800);
const tickColorAfter = await page.evaluate(() => {
  const el = document.querySelector("[phx-hook=ChartHook]");
  return getComputedStyle(el).getPropertyValue("--viz-series").trim();
});
check(
  "dark theme swaps chart tokens",
  tickColorBefore !== tickColorAfter,
  `${tickColorBefore} -> ${tickColorAfter}`,
);
await page.screenshot({ path: `${out}/06-dark.png`, fullPage: true });

await page.evaluate(() => {
  localStorage.removeItem("phx:theme");
  document.documentElement.setAttribute("data-theme", "light");
});

// Chart axis and server header must agree on time zone and number format
const header = await tempWrapper.locator(".font-mono.font-bold").innerText();
const headerTime = await tempWrapper
  .locator(".font-mono.font-bold + span")
  .innerText();
await temp.hover({
  position: { x: (await temp.boundingBox()).width - 12, y: 120 },
});
await page.waitForTimeout(400);
const tooltipTitle = await page.evaluate(() => {
  const el = document.querySelector(
    "[phx-hook=ChartHook][data-label=temperature] canvas",
  );
  return el.getAttribute("aria-label");
});
check(
  "header value uses dot decimals",
  /^\d+\.\d{2}$/.test(header.trim()),
  header.trim(),
);
check(
  "aria summary matches header value",
  tooltipTitle.endsWith(header.trim()),
  `${tooltipTitle} vs ${header.trim()}`,
);
await temp
  .locator("xpath=ancestor::div[contains(@class,'chart-wrapper')]")
  .screenshot({ path: `${out}/07-utc-axis.png` });
console.log("header time (UTC):", headerTime.trim());

check(
  "no console errors",
  consoleErrors.length === 0,
  consoleErrors.slice(0, 3).join(" | "),
);

await page.waitForTimeout(3000);
await browser.close();

const failed = results.filter((r) => !r.ok).length;
console.log(`\n${results.length - failed}/${results.length} checks passed`);
process.exit(failed ? 1 : 0);
