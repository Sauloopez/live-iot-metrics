// Data extraction over USB (/devices/sync) against a simulated isolated node: credits,
// confirmations that release data, a damaged frame that must be resent, no duplicates on a
// second extraction, and the node clock corrected at the end.
// Usage: node device_sync.mjs [measurements]
import { installFakeNode } from "./fake_node.mjs";
import {
  BASE_URL,
  checker,
  fakeMac,
  gotoLive,
  launch,
  shot,
  waitForLiveView,
} from "./support.mjs";

const TOTAL = Number(process.argv[2] || 1000);
const MAC = fakeMac(1);
const t = checker(`Extract data via USB (${TOTAL} measurements)`);
const { browser, page, errors } = await launch();
await installFakeNode(page, {
  mac: MAC,
  measurements: TOTAL,
  corruptAfterSeq: 300,
  sensors: [
    {
      i: 1,
      p: 26,
      t: "water_temperature",
      dr: "ds18b20",
      pr: 1,
      o: 0,
      iv: 60000,
    },
  ],
});

await gotoLive(page, "/devices");
await page.click("#device-sync-link");
await page.waitForURL("**/devices/sync");
await waitForLiveView(page);
await page.click("#btn-connect");
await page.waitForSelector("#node-summary");
await page.waitForFunction(
  () => document.querySelector("#node-pending")?.textContent.trim() !== "—",
);
const pendingBefore = Number((await page.innerText("#node-pending")).trim());
t.check(
  "node summary shows the pending measurements",
  pendingBefore > 0,
  `${pendingBefore} pending`,
);

const started = Date.now();
await page.click("#btn-extract");
await page.waitForSelector("#progress-saved");
await page.waitForTimeout(800);
await shot(page, "device-sync-running");
await page.waitForSelector("#sync-result", { timeout: 120000 });
const seconds = (Date.now() - started) / 1000;
await page.waitForTimeout(500);
await shot(page, "device-sync-done");

const result = await page.innerText("#sync-result");
t.check(
  "extraction finished",
  /Extraction finished/.test(result),
  result.replace(/\s+/g, " "),
);
t.check(
  "every pending measurement saved once",
  result.includes(`${pendingBefore} saved`),
);
const node = await page.evaluate(() => window.__node);
t.check(
  "node released everything after the confirmation",
  node.acked === TOTAL,
  `acked ${node.acked}`,
);
t.check(
  "credit limited the data in flight",
  node.maxInFlight <= 256 + 16,
  `max in flight ${node.maxInFlight}`,
);
t.check(
  "damaged frame detected and resent",
  node.sent > pendingBefore,
  `${node.sent} sent for ${pendingBefore}`,
);
t.check(
  "node clock corrected at the end",
  Math.abs(node.clock - Date.now() / 1000) < 60,
);
console.log(
  `throughput: ${(pendingBefore / seconds).toFixed(0)} measurements/s (${seconds.toFixed(1)} s with UI waits)`,
);

await page.click("#btn-extract");
await page.waitForFunction(
  () =>
    /0 saved/.test(document.querySelector("#sync-result")?.textContent || ""),
  null,
  {
    timeout: 30000,
  },
);
t.check("a second extraction stores nothing new", true);

await t.finish(browser, errors);
