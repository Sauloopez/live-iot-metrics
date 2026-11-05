// Simulated node behind navigator.serial for the end-to-end tests.
//
// Speaks the firmware serial API (docs/tundra/SERIAL_API.md): one JSON command per line,
// responses with short keys, and `sync` DATA frames as 0x00 · COBS(frame) · 0x00 with CBOR
// measurements and CRC-16. The node state is exposed as `window.__node` for assertions.
//
// Options:
//   mac, variant       what `info` reports (default variant "isolated")
//   measurements       how many stored measurements to offer to `sync` (default 0)
//   sensors            sensors stored on the node, as `sensor list` items {i, p, t, dr, pr, o, iv}
//   battery            {mv, p} reported by `status`
//   corruptAfterSeq    damage the first frame that starts after this seq (tests the resume)

export async function installFakeNode(page, options) {
  await page.addInitScript(fakeNode, {
    variant: "isolated",
    measurements: 0,
    sensors: [],
    battery: { mv: 3912, p: 69 },
    corruptAfterSeq: null,
    ...options,
  });
}

// Runs inside the page: must be self contained
function fakeNode({
  mac,
  variant,
  measurements,
  sensors,
  battery,
  corruptAfterSeq,
}) {
  const T0 = 1762164450;
  const node = {
    mac,
    variant,
    nextSeq: measurements + 1,
    acked: 0,
    cursor: 0,
    credit: 0,
    streaming: false,
    frameNo: 0,
    corruptAfterSeq,
    maxInFlight: 0,
    sent: 0,
    clock: 0,
    sensors: new Map(sensors.map((s) => [s.i, s])),
    commands: [],
  };
  window.__node = node;

  let controller;
  const encoder = new TextEncoder();
  const reply = (obj) =>
    setTimeout(
      () => controller.enqueue(encoder.encode(JSON.stringify(obj) + "\n")),
      15,
    );

  // --- Binary frames, same encoding as the firmware ---
  const uint = (v) =>
    v < 24
      ? [v]
      : v < 256
        ? [0x18, v]
        : v < 65536
          ? [0x19, v >> 8, v & 255]
          : [
              0x1a,
              (v >>> 24) & 255,
              (v >>> 16) & 255,
              (v >>> 8) & 255,
              v & 255,
            ];
  const float32 = (x) => {
    const view = new DataView(new ArrayBuffer(4));
    view.setFloat32(0, x);
    return [0xfa, ...new Uint8Array(view.buffer)];
  };
  const record = (seq) => [
    0x84,
    ...uint(seq),
    ...uint(T0 + seq * 60),
    ...uint(1),
    ...float32(20 + (seq % 10) / 4),
  ];
  const crc16 = (bytes) => {
    let crc = 0xffff;
    for (const b of bytes) {
      crc ^= b << 8;
      for (let i = 0; i < 8; i++)
        crc =
          crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
    return crc;
  };
  const cobs = (bytes) => {
    const out = [0];
    let codeIndex = 0;
    let code = 1;
    for (const b of bytes) {
      if (b === 0) {
        out[codeIndex] = code;
        codeIndex = out.length;
        out.push(0);
        code = 1;
      } else {
        out.push(b);
        if (++code === 0xff) {
          out[codeIndex] = code;
          codeIndex = out.length;
          out.push(0);
          code = 1;
        }
      }
    }
    out[codeIndex] = code;
    return out;
  };

  const pump = () => {
    if (!node.streaming || node.credit === 0) return;
    const count = Math.min(16, node.credit, node.nextSeq - node.cursor);
    if (count <= 0) {
      node.streaming = false;
      reply({ s: "ok", m: "Stream end", l: node.nextSeq - 1 });
      return;
    }
    const first = node.cursor;
    const records = [];
    for (let s = first; s < first + count; s++) records.push(...record(s));
    const frame = [
      0x01,
      node.frameNo & 255,
      node.frameNo >> 8,
      first & 255,
      (first >> 8) & 255,
      (first >> 16) & 255,
      first >>> 24,
      count,
      ...records,
    ];
    const crc = crc16(frame);
    frame.push(crc & 255, crc >> 8);
    if (node.corruptAfterSeq !== null && first > node.corruptAfterSeq) {
      frame[12] ^= 0x10; // a bit flipped on the wire
      node.corruptAfterSeq = null;
    }
    controller.enqueue(Uint8Array.from([0, ...cobs(frame), 0]));
    node.cursor += count;
    node.credit -= count;
    node.frameNo++;
    node.sent += count;
    node.maxInFlight = Math.max(node.maxInFlight, node.cursor - 1 - node.acked);
    setTimeout(pump, 2);
  };

  // --- Commands ---
  const sensorFromCommand = (d) => ({
    i: d.id,
    p: d.pin,
    t: d.type,
    dr: d.driver,
    pr: d.precision,
    o: d.offset,
    iv: d.interval,
  });

  const handle = (cmd) => {
    node.commands.push(cmd);
    const d = cmd.data || {};
    switch (cmd.command) {
      case "ping":
        return reply({ s: "ok", m: "pong" });
      case "info":
        return reply({ s: "ok", mc: node.mac, v: node.variant });
      case "wifi":
      case "coap":
        return reply({ s: "ok", m: "saved" });
      case "time":
        if (d.action === "set") node.clock = d.ts;
        return reply({ s: "ok", m: "Time set" });
      case "status":
        return reply({
          s: "ok",
          c: { t: node.clock || T0, v: true },
          b: battery,
          st: {
            n: node.nextSeq,
            a: node.acked,
            pd: node.nextSeq - 1 - node.acked,
            f: 1500000,
            tt: 2228224,
            fw: 0,
          },
          pw: { bc: 42, aw: 60000, rr: 8 },
        });
      case "sensor":
        if (d.action === "list")
          return reply({ s: "ok", d: [...node.sensors.values()] });
        if (d.action === "add") {
          if (node.sensors.has(d.id))
            return reply({ s: "error", m: "Failed to add sensor" });
          node.sensors.set(d.id, sensorFromCommand(d));
          return reply({ s: "ok", m: "Sensor added" });
        }
        if (d.action === "update") {
          if (!node.sensors.has(d.id))
            return reply({ s: "error", m: "Failed to update sensor" });
          node.sensors.set(d.id, sensorFromCommand(d));
          return reply({ s: "ok", m: "Sensor updated" });
        }
        if (d.action === "remove") {
          if (!node.sensors.delete(d.id))
            return reply({ s: "error", m: "Failed to remove sensor" });
          return reply({ s: "ok", m: "Sensor removed" });
        }
        break;
      case "sync":
        if (d.action === "status")
          return reply({
            s: "ok",
            n: node.nextSeq,
            a: node.acked,
            pd: node.nextSeq - 1 - node.acked,
          });
        if (d.action === "stream") {
          node.cursor = Math.max(d.from, node.acked + 1);
          node.credit = d.credit;
          node.frameNo = 0;
          node.streaming = true;
          reply({ s: "ok", m: "Stream started" });
          setTimeout(pump, 30);
          return;
        }
        if (d.action === "credit") {
          if (d.ack > node.acked)
            node.acked = Math.min(d.ack, node.nextSeq - 1);
          node.credit += d.credit;
          reply({ s: "ok", a: node.acked });
          setTimeout(pump, 20);
          return;
        }
        if (d.action === "stop") {
          node.streaming = false;
          return reply({ s: "ok", m: "Stream stopped" });
        }
        break;
    }
    reply({ s: "error", m: "Unknown command" });
  };

  // Like a real SerialPort: fresh streams every time it is opened
  let pending = "";
  const port = {
    async open() {
      pending = "";
      port.readable = new ReadableStream({ start: (c) => (controller = c) });
      port.writable = new WritableStream({
        write(chunk) {
          pending += new TextDecoder().decode(chunk);
          const lines = pending.split("\n");
          pending = lines.pop();
          lines.filter(Boolean).forEach((line) => handle(JSON.parse(line)));
        },
      });
    },
    async close() {
      node.streaming = false;
    },
  };

  Object.defineProperty(navigator, "serial", {
    value: {
      requestPort: async () => port,
      addEventListener() {},
      removeEventListener() {},
    },
  });
}
