// Store-and-forward over CoAP: a simulated node with local storage (coap_sync.exs) pushes its
// measurements over real CoAP/UDP with a lost frame on the way; every measurement must end up
// confirmed exactly once, and Devices must show the node with its status sent over CoAP.
// Usage: node coap_sync.mjs [measurements]
import { spawnSync } from "node:child_process";
import {
  BASE_URL,
  ROOT_DIR,
  checker,
  fakeMac,
  gotoLive,
  launch,
  shot,
} from "./support.mjs";

const TOTAL = Number(process.argv[2] || 500);
// A fresh MAC per run: the running server caches watermarks in memory, and cleanup.exs only
// clears the database
const MAC = fakeMac(0x40 + Math.floor(Math.random() * 0xbf));
const t = checker(`Store and forward over CoAP (${TOTAL} measurements)`);
const { browser, page, errors } = await launch({
  viewport: { width: 1400, height: 900 },
});

const started = Date.now();
const run = spawnSync(
  "mix",
  ["run", "--no-start", "e2e/coap_sync.exs", MAC, String(TOTAL)],
  {
    cwd: ROOT_DIR,
    encoding: "utf8",
  },
);
const seconds = (Date.now() - started) / 1000;
const summary = (run.stdout.match(/ACKED=\d+ EXCHANGES=\d+ RESENT=-?\d+/) || [
  "",
])[0];
const value = (key) =>
  Number((summary.match(new RegExp(`${key}=(-?\\d+)`)) || [])[1]);

t.check(
  "simulated node ran",
  run.status === 0,
  run.status === 0 ? summary : run.stderr.slice(-300),
);
t.check(
  "server confirmed every measurement",
  value("ACKED") === TOTAL,
  `acked ${value("ACKED")}`,
);
t.check(
  "the lost frame was resent",
  value("RESENT") > 0,
  `${value("RESENT")} measurements resent`,
);
// One exchange per 16 measurements is the minimum; waiting for the async server adds a few
const minimum = Math.ceil(TOTAL / 16);
t.check(
  "no flooding while the server processes",
  value("EXCHANGES") <= minimum * 3,
  `${value("EXCHANGES")} exchanges, minimum ${minimum}`,
);
console.log(
  `${value("EXCHANGES")} CoAP exchanges in ${seconds.toFixed(1)} s (includes mix startup)`,
);

await gotoLive(page, "/devices");
const row = page.locator("#nodes-table tr", { hasText: MAC });
await row.waitFor();
const text = (await row.innerText()).replace(/\s+/g, " ");
t.check("node registered by its first CoAP request", true);
t.check("battery from the CoAP status", text.includes("74%"), text);
t.check(
  "sensor typed from the sensor list",
  text.includes("water_temperature"),
);

await row.locator("[id^=manage-node-]").click();
await page.waitForSelector("#node-health-reports");
t.check(
  "status report arrived over CoAP",
  (await page.innerText("#node-health-reports")).includes("coap"),
);
await shot(page, "coap-sync-modal");

await t.finish(browser, errors);
