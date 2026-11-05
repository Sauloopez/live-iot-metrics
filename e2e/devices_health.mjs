// Node health in Devices: a simulated isolated node with a low battery and data it has not
// synchronized reports its status over USB (/devices/sync); Devices must show the battery,
// storage, "last seen" and the matching alerts, and the node modal its report history.
import { installFakeNode } from "./fake_node.mjs";
import {
  BASE_URL,
  checker,
  fakeMac,
  gotoLive,
  launch,
  shot,
} from "./support.mjs";

const MAC = fakeMac(2);
const t = checker("Node health in Devices");
const { browser, page, errors } = await launch({
  viewport: { width: 1400, height: 900 },
});
await installFakeNode(page, {
  mac: MAC,
  measurements: 50,
  battery: { mv: 3610, p: 15 },
});

// Connecting is enough: the screen saves the `status` the node reports
await gotoLive(page, "/devices/sync");
await page.click("#btn-connect");
await page.waitForFunction(() =>
  document.querySelector("#node-battery")?.textContent.includes("15%"),
);
t.check("status received over USB", true);

await gotoLive(page, "/devices");
await page.waitForSelector("#nodes-table");
const row = page.locator("#nodes-table tr", { hasText: MAC });
await row.waitFor();
const text = (await row.innerText()).replace(/\s+/g, " ");
t.check("battery shown", text.includes("15%"), text);
t.check("storage and pending shown", text.includes("50 pending"));
t.check("seen just now", text.includes("just now"));
t.check("low battery alert", text.includes("Low battery"));
t.check(
  "sync overdue alert (pending data never synchronized)",
  text.includes("Sync overdue"),
);
await shot(page, "devices-health");

await row.locator("[id^=manage-node-]").click();
await page.waitForSelector("#node-health-reports");
t.check(
  "node modal lists the report",
  (await page.innerText("#node-health-reports")).includes("3610 mV"),
);
await shot(page, "devices-health-modal");

await t.finish(browser, errors);
