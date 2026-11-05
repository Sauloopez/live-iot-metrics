// Device setup over USB (/devices/setup) against a simulated node: identify it by MAC, add a
// sensor from a preset (saved with a system id and sent to the node), edit it, detect a value
// changed on the node, resend everything, and delete all sensors on both sides.
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

const MAC = fakeMac(3);
const t = checker("Device setup over USB");
const { browser, page, errors } = await launch({
  viewport: { width: 1350, height: 1300 },
});
// The node already has a sensor that the database does not know about
await installFakeNode(page, {
  mac: MAC,
  variant: "coap",
  sensors: [
    { i: 999, p: 4, t: "leftover", dr: "analog", pr: 1, o: 0, iv: 10000 },
  ],
});

await gotoLive(page, "/devices");
await page.click("#device-setup-link");
await page.waitForURL("**/devices/setup");
await waitForLiveView(page);
t.check(
  "sensors locked before connecting",
  await page.isVisible("#sensors-locked"),
);

await page.click("#btn-connect");
await page.waitForSelector("#node-mac", { timeout: 10000 });
t.check("node identified by MAC", (await page.innerText("#node-mac")) === MAC);
await page.waitForSelector("#orphan-999");
t.check("sensor only on the node is listed", true);
t.check(
  "WiFi panel enabled after connecting",
  await page.isEnabled("#btn-set-wifi"),
);

// Add from a preset
await page.selectOption("#sensor-preset", "soil");
await page.waitForFunction(
  () =>
    document.querySelector(
      "#sensor-form input[name='node_sensor_config[sensor_type]']",
    ).value === "soil_moisture",
);
t.check("preset fills the form", true);
await page.click("#btn-save-sensor");
const row = page.locator("#sensor-configs tr[id^='configs-']").first();
await row.waitFor();
const id = (await row.getAttribute("id")).replace("configs-", "");
await page.waitForSelector(`#sync-status-${id}:has-text("Synced")`, {
  timeout: 10000,
});
const add = await page.evaluate(
  (sid) =>
    window.__node.commands.find(
      (c) => c.data?.action === "add" && c.data.id === Number(sid),
    ),
  id,
);
t.check(
  "saved with a system id and sent to the node",
  Boolean(add),
  JSON.stringify(add?.data),
);

// Edit
await page.click(`#edit-sensor-${id}`);
await page.fill("input[name='node_sensor_config[interval_ms]']", "20000");
await page.click("#btn-save-sensor");
await page.waitForFunction(
  (sid) => window.__node.sensors.get(Number(sid))?.iv === 20000,
  id,
  { timeout: 10000 },
);
await page.waitForSelector(`#sync-status-${id}:has-text("Synced")`);
t.check("edit sends an update and stays synced", true);

// A change made directly on the node is detected after reconnecting
await page.evaluate(
  (sid) => (window.__node.sensors.get(Number(sid)).p = 35),
  id,
);
await page.click("#btn-disconnect");
await page.waitForSelector("#sensors-locked");
await page.click("#btn-connect");
await page.waitForSelector(`#sync-status-${id}:has-text("Differs")`, {
  timeout: 10000,
});
t.check("value changed on the node is flagged", true);
await shot(page, "device-setup-differs");

await page.click("#btn-sync-all");
await page.waitForSelector(`#sync-status-${id}:has-text("Synced")`, {
  timeout: 10000,
});
t.check("send all re-syncs the node", true);

// Delete all: database and node, including the sensor only on the node
await page.click("#btn-delete-all");
await page.waitForSelector("#sensor-configs-empty", {
  state: "visible",
  timeout: 10000,
});
await page.waitForFunction(() => window.__node.sensors.size === 0, null, {
  timeout: 10000,
});
t.check("delete all empties the database and the node", true);
t.check(
  "terminal shows the conversation",
  (await page.innerText("#serial-terminal")).includes('"action":"remove"'),
);
await shot(page, "device-setup-deleted");

await t.finish(browser, errors);
