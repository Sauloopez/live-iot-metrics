// Web Serial transport for the device setup and data extraction screens.
//
// The LiveView owns the UI state; this hook only moves bytes:
//   * connects to the node and reports it (`serial_connected`, `node_identified`, `node_sensors`)
//   * runs the commands the server pushes (`serial_commands`) one at a time, waiting for each
//     JSON response so the ESP32 serial buffer never overflows, then refreshes the sensor list
//   * answers single requests from the server (`serial_request` -> `serial_response`)
//   * runs data extractions (`sync_start` / `sync_stop`, see ../serial/sync_engine.js)
//   * sends WiFi / CoAP settings straight from the browser (the WiFi password never reaches
//     the server)
import { FrameReader } from "../serial/frame_reader";
import { SyncEngine } from "../serial/sync_engine";

// The node answers with one or two character keys to keep lines short
// (iot-node/src/shared/presentation/controllers/SerialProtocol.h, docs/tundra/SERIAL_API.md):
// {"s": "ok" | "error", "m": message, ...command specific keys}
const expandSensor = (s) => ({
  id: s.i,
  pin: s.p,
  type: s.t,
  driver: s.dr,
  precision: s.pr,
  offset: s.o,
  interval: s.iv,
});

const RESPONSE_TIMEOUT_MS = 20000;
const BOOT_SETTLE_MS = 2500;

export const WebSerialHook = {
  mounted() {
    this.port = null;
    this.reader = null;
    this.writer = null;
    this.keepReading = false;
    this.pending = null;
    this.queue = Promise.resolve();
    this.terminal = this.el.querySelector("#serial-terminal");

    // Buttons may be re-rendered by LiveView, so listen on the hook element
    this.onClick = (e) => {
      const target = e.target.closest("[data-serial-action]");
      if (!target || target.disabled) return;

      switch (target.dataset.serialAction) {
        case "connect":
          this.connect();
          break;
        case "disconnect":
          this.disconnect();
          break;
        case "set-wifi":
          this.setWifi();
          break;
        case "set-coap":
          this.setCoap();
          break;
        case "clear-terminal":
          this.terminal.textContent = "";
          break;
      }
    };
    this.el.addEventListener("click", this.onClick);

    this.handleEvent("serial_commands", ({ commands }) => this.runCommands(commands));

    this.handleEvent("serial_request", async ({ ref, command }) => {
      try {
        const response = await this.enqueue(command);
        this.pushEvent("serial_response", { ref, ok: true, response });
      } catch (e) {
        this.pushEvent("serial_response", { ref, ok: false, message: e.message });
      }
    });

    this.sync = new SyncEngine({
      send: (command) => this.enqueue(command),
      push: (event, payload) => new Promise((resolve) => this.pushEvent(event, payload, resolve)),
      log: (text) => this.log(text),
    });
    this.handleEvent("sync_start", ({ acked }) =>
      this.sync.start({ acked }).catch((e) => this.sync.stop(e.message)),
    );
    this.handleEvent("sync_stop", () => this.sync.stop());

    if (!("serial" in navigator)) {
      this.log("Web Serial is not available in this browser. Use Chrome, Edge or Brave.");
      this.pushEvent("serial_unsupported", {});
    }
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    if (this.onSerialDisconnect) {
      navigator.serial.removeEventListener("disconnect", this.onSerialDisconnect);
    }
    this.disconnect({ silent: true });
  },

  log(msg) {
    this.terminal.textContent += msg + "\n";
    this.terminal.scrollTop = this.terminal.scrollHeight;
  },

  setPanelEnabled(enabled) {
    this.el
      .querySelectorAll("[data-serial-panel] [data-serial-action]")
      .forEach((btn) => (btn.disabled = !enabled));
  },

  async connect() {
    try {
      this.port = await navigator.serial.requestPort();
      await this.port.open({ baudRate: 115200 });
    } catch (e) {
      this.port = null;
      if (e.name !== "NotFoundError") this.log("Connection failed: " + e.message);
      return;
    }

    this.log("Connected to serial port at 115200");
    if (!this.onSerialDisconnect) {
      // Fires when the USB device goes away (unplugged, reset by another program, etc.)
      this.onSerialDisconnect = (event) => {
        if (event.target === this.port) this.handleLostPort();
      };
      navigator.serial.addEventListener("disconnect", this.onSerialDisconnect);
    }

    this.keepReading = true;
    this.readLoop();
    this.setPanelEnabled(true);
    this.pushEvent("serial_connected", {});

    // Opening the port can reset the board; give it a moment before talking to it
    await new Promise((r) => setTimeout(r, BOOT_SETTLE_MS));

    try {
      const info = await this.enqueue({ command: "info" });
      if (!info.mc) throw new Error("the node did not report its MAC; update the firmware");
      this.pushEvent("node_identified", { mac: info.mc, variant: info.v });
      await this.refreshSensors();
    } catch (e) {
      this.log("Could not identify the node: " + e.message);
      this.pushEvent("node_error", { message: e.message });
    }
  },

  async disconnect({ silent = false, message = "Disconnected" } = {}) {
    if (!this.port) return;
    const port = this.port;
    this.port = null;
    this.keepReading = false;
    this.rejectPending(new Error("port closed"));
    if (this.sync?.running) this.sync.state = null;

    if (this.reader) await this.reader.cancel().catch(() => {});
    if (this.writer) {
      await this.writer.close().catch(() => {});
      this.writer.releaseLock();
    }
    await port.close().catch((e) => console.log(e));

    this.reader = null;
    this.writer = null;
    this.readableClosed = null;

    if (silent) return;
    this.log(message);
    this.setPanelEnabled(false);
    this.pushEvent("serial_disconnected", { message });
  },

  handleLostPort() {
    return this.disconnect({
      message: "Device lost: it was unplugged, reset, or opened by another program. Connect again.",
    });
  },

  // Reads raw bytes: JSON lines and binary sync frames share the port
  async readLoop() {
    this.reader = this.port.readable.getReader();
    this.writer = this.port.writable.getWriter();

    const frames = new FrameReader({
      onLine: (line) => this.handleLine(line),
      onFrame: (frame) => this.sync.onFrame(frame),
    });
    try {
      while (this.keepReading) {
        const { value, done } = await this.reader.read();
        if (done) break;
        if (value) frames.push(value);
      }
    } catch (e) {
      this.log("Read error: " + e.message);
    } finally {
      this.reader?.releaseLock();
    }

    // The loop ended without the user asking for it: the port is gone
    if (this.keepReading) await this.handleLostPort();
  },

  handleLine(line) {
    if (!line) return;
    this.log("<- " + line);

    // Firmware log lines and JSON responses can share a line; take the JSON part
    const start = line.indexOf('{"s":');
    if (start < 0) return;

    let response;
    try {
      response = JSON.parse(line.slice(start));
    } catch (_e) {
      return;
    }
    // Messages the node prints on its own, not answers to our commands
    if (response.m === "Stream end") return this.sync.onStreamEnd(response.l);
    if (response.m === "Serial controller ready" || response.m === "Service mode idle, going to sleep") return;

    if (!this.pending) return;
    const { resolve, timer } = this.pending;
    clearTimeout(timer);
    this.pending = null;
    resolve(response);
  },

  rejectPending(error) {
    if (!this.pending) return;
    clearTimeout(this.pending.timer);
    this.pending.reject(error);
    this.pending = null;
  },

  // Serializes commands: each one waits for the previous response
  enqueue(command) {
    const run = this.queue.then(() => this.send(command));
    this.queue = run.catch(() => {});
    return run;
  },

  async send(command) {
    if (!this.writer) throw new Error("not connected");

    const line = JSON.stringify(command);
    const response = new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending = null;
        reject(new Error("no response from the node"));
      }, RESPONSE_TIMEOUT_MS);
      this.pending = { resolve, reject, timer };
    });

    // Logged before writing: the answer can arrive before the write resolves
    const shown =
      command.command === "wifi" && command.data?.password
        ? JSON.stringify({ ...command, data: { ...command.data, password: "••••••" } })
        : line;
    this.log("-> " + shown);
    try {
      await this.writer.write(new TextEncoder().encode(line + "\n"));
    } catch (e) {
      this.rejectPending(e);
      this.handleLostPort();
    }

    const result = await response;
    if (result.s !== "ok") throw new Error(result.m || "command failed");
    return result;
  },

  async runCommands(commands) {
    const results = [];
    for (const command of commands) {
      try {
        const response = await this.enqueue(command);
        results.push({ command, ok: true, message: response.m || "ok" });
      } catch (e) {
        results.push({ command, ok: false, message: e.message });
      }
    }
    this.pushEvent("serial_commands_done", { results });
    await this.refreshSensors();
  },

  async refreshSensors() {
    try {
      const response = await this.enqueue({ command: "sensor", data: { action: "list" } });
      this.pushEvent("node_sensors", { sensors: (response.d || []).map(expandSensor) });
    } catch (e) {
      this.log("Could not read sensors from the node: " + e.message);
    }
  },

  async setWifi() {
    const ssid = this.el.querySelector("#wifi-ssid").value;
    const password = this.el.querySelector("#wifi-pass").value;
    await this.enqueue({ command: "wifi", data: { action: "set", ssid, password } }).catch((e) =>
      this.log("WiFi not saved: " + e.message),
    );
  },

  async setCoap() {
    const host = this.el.querySelector("#coap-host").value;
    const port = parseInt(this.el.querySelector("#coap-port").value || "5683");
    await this.enqueue({ command: "coap", data: { action: "set", host, port } }).catch((e) =>
      this.log("CoAP not saved: " + e.message),
    );
  },
};
