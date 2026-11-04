// End-to-end test of /devices/sync against a simulated isolated node that speaks the real
// protocol: COBS + CRC-16 frames of CBOR measurements, credits, acks that release data, and
// one frame damaged on purpose to exercise the resume path.
//
// Needs the server running (`mix phx.server`) and Playwright:
//   PLAYWRIGHT_DIR=<dir containing node_modules/playwright> CHROME_PATH=<chrome binary> \
//     node test/e2e/device_sync.mjs [mac] [measurements]
// Uses a fake MAC; delete its rows afterwards (nodes and node_sync_states).
import { createRequire } from "node:module";
const require = createRequire(process.env.PLAYWRIGHT_DIR ? `${process.env.PLAYWRIGHT_DIR}/` : import.meta.url);
const { chromium } = require("playwright");
const MAC = process.argv[2] || "02:00:00:00:E2:E3";
const TOTAL = Number(process.argv[3] || 1000);
const results = [];
const check = (n, ok, d = "") => { results.push(ok); console.log(`${ok ? "PASS" : "FAIL"}  ${n}${d ? " — " + d : ""}`); };

const fakeNode = ({ MAC, TOTAL }) => {
  const T0 = 1762164450;
  const node = { nextSeq: TOTAL + 1, acked: 0, cursor: 0, credit: 0, streaming: false, frameNo: 0,
                 corruptOnce: true, maxInFlight: 0, sent: 0, clock: 0, log: [] };
  window.__node = node;
  let controller;
  const enc = new TextEncoder();
  const emitLine = (obj) => controller.enqueue(enc.encode(JSON.stringify(obj) + "\n"));

  const uint = (v) => v < 24 ? [v] : v < 256 ? [0x18, v] : v < 65536 ? [0x19, v >> 8, v & 255]
    : [0x1a, (v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255];
  const f32 = (x) => { const b = new DataView(new ArrayBuffer(4)); b.setFloat32(0, x); return [0xfa, ...new Uint8Array(b.buffer)]; };
  const record = (seq) => [0x84, ...uint(seq), ...uint(T0 + seq * 60), ...uint(1), ...f32(20 + (seq % 10) / 4)];
  const crc16 = (bytes) => { let c = 0xffff; for (const x of bytes) { c ^= x << 8; for (let i = 0; i < 8; i++) c = c & 0x8000 ? ((c << 1) ^ 0x1021) & 0xffff : (c << 1) & 0xffff; } return c; };
  const cobs = (bytes) => { const out = [0]; let ci = 0, code = 1;
    for (const b of bytes) { if (b === 0) { out[ci] = code; ci = out.length; out.push(0); code = 1; }
      else { out.push(b); code++; if (code === 0xff) { out[ci] = code; ci = out.length; out.push(0); code = 1; } } }
    out[ci] = code; return out; };

  const pump = () => {
    if (!node.streaming) return;
    if (node.credit === 0) return;
    const count = Math.min(16, node.credit, node.nextSeq - node.cursor);
    if (count <= 0) { node.streaming = false; emitLine({ s: "ok", m: "Stream end", l: node.nextSeq - 1 }); return; }
    const first = node.cursor;
    const recs = []; for (let s = first; s < first + count; s++) recs.push(...record(s));
    const frame = [0x01, node.frameNo & 255, node.frameNo >> 8, first & 255, (first >> 8) & 255, (first >> 16) & 255, first >>> 24, count, ...recs];
    const crc = crc16(frame); frame.push(crc & 255, crc >> 8);
    if (node.corruptOnce && first > 300) { frame[12] ^= 0x10; node.corruptOnce = false; }  // damaged on the wire
    controller.enqueue(Uint8Array.from([0, ...cobs(frame), 0]));
    node.cursor += count; node.credit -= count; node.frameNo++; node.sent += count;
    node.maxInFlight = Math.max(node.maxInFlight, node.cursor - 1 - node.acked);
    setTimeout(pump, 2);
  };

  const handle = (cmd) => {
    node.log.push(cmd);
    const d = cmd.data || {};
    switch (cmd.command) {
      case "info": return emitLine({ s: "ok", mc: MAC, v: "isolated" });
      case "sensor": return emitLine({ s: "ok", d: [{ i: 1, p: 26, t: "water_temperature", dr: "ds18b20", pr: 1, o: 0, iv: 60000 }] });
      case "status": return emitLine({ s: "ok", c: { t: T0, v: true }, b: { mv: 3912, p: 69 },
        st: { n: node.nextSeq, a: node.acked, pd: node.nextSeq - 1 - node.acked, f: 1500000, tt: 2228224, fw: 0 }, pw: { bc: 42, aw: 60000, rr: 8 } });
      case "time": node.clock = d.ts; return emitLine({ s: "ok", m: "Time set" });
      case "sync":
        if (d.action === "status") return emitLine({ s: "ok", n: node.nextSeq, a: node.acked, pd: node.nextSeq - 1 - node.acked });
        if (d.action === "stream") { node.cursor = Math.max(d.from, node.acked + 1); node.credit = d.credit; node.frameNo = 0; node.streaming = true;
          emitLine({ s: "ok", m: "Stream started" }); setTimeout(pump, 5); return; }
        if (d.action === "credit") { if (d.ack > node.acked) node.acked = Math.min(d.ack, node.nextSeq - 1);
          node.credit += d.credit; emitLine({ s: "ok", a: node.acked }); setTimeout(pump, 2); return; }
        if (d.action === "stop") { node.streaming = false; return emitLine({ s: "ok", m: "Stream stopped" }); }
    }
    emitLine({ s: "error", m: "Unknown command" });
  };

  let pending = "";
  const port = {
    async open() {
      port.readable = new ReadableStream({ start(c) { controller = c; } });
      port.writable = new WritableStream({ write(chunk) {
        pending += new TextDecoder().decode(chunk);
        const lines = pending.split("\n"); pending = lines.pop();
        lines.filter(Boolean).forEach((l) => handle(JSON.parse(l)));
      } });
    },
    async close() {},
  };
  Object.defineProperty(navigator, "serial", { value: { requestPort: async () => port, addEventListener() {}, removeEventListener() {} } });
};

const browser = await chromium.launch({ headless: process.env.HEADLESS === "1", slowMo: 80, executablePath: process.env.CHROME_PATH });
const page = await browser.newPage({ viewport: { width: 1300, height: 1100 } });
await page.addInitScript(fakeNode, { MAC, TOTAL });
const errors = []; page.on("pageerror", (e) => errors.push(e.message));

await page.goto("http://localhost:4000/devices");
await page.click("#device-sync-link");
await page.waitForURL("**/devices/sync");
await page.click("#btn-connect");
await page.waitForSelector("#node-summary");
await page.waitForFunction(() => document.querySelector("#node-pending")?.textContent.trim() !== "—");
check("node summary shows pending measurements", (await page.innerText("#node-pending")).trim() === String(TOTAL));

const t0 = Date.now();
await page.click("#btn-extract");
await page.waitForSelector("#progress-saved");
await page.waitForTimeout(1500);
await page.screenshot({ path: "/tmp/device-sync-running.png", fullPage: true });
await page.waitForSelector("#sync-result", { timeout: 120000 });
const secs = (Date.now() - t0) / 1000;
await page.waitForTimeout(800);
await page.screenshot({ path: "/tmp/device-sync-done.png", fullPage: true });

const result = await page.innerText("#sync-result");
check("extraction finished", /Extraction finished/.test(result), result.replace(/\s+/g, " "));
check("every measurement saved once", result.includes(`${TOTAL} saved`));
const node = await page.evaluate(() => window.__node);
check("node released everything after confirmation", node.acked === TOTAL, `acked ${node.acked}`);
check("credit limited data in flight", node.maxInFlight <= 256 + 16, `max in flight ${node.maxInFlight}`);
check("damaged frame was resent", node.sent > TOTAL, `${node.sent} sent for ${TOTAL}`);
check("node clock corrected at the end", Math.abs(node.clock - Date.now() / 1000) < 60);
check("no page errors", errors.length === 0, errors.join(" | "));
console.log(`throughput: ${(TOTAL / secs).toFixed(0)} measurements/s (${secs.toFixed(1)} s, includes UI waits)`);

// Second extraction: nothing new
await page.click("#btn-extract");
await page.waitForFunction(() => /Extraction finished/.test(document.querySelector("#sync-result")?.textContent || ""), null, { timeout: 30000 });
await page.waitForTimeout(500);
check("second extraction stores nothing new", (await page.innerText("#sync-result")).includes("0 saved"));
await browser.close();
process.exit(results.every(Boolean) ? 0 : 1);
