export const WebSerialHook = {
  mounted() {
    this.port = null;
    this.reader = null;
    this.writer = null;
    this.keepReading = true;

    this.btnConnect = this.el.querySelector("#btn-connect");
    this.btnDisconnect = this.el.querySelector("#btn-disconnect");
    this.btnSetWifi = this.el.querySelector("#btn-set-wifi");
    this.btnSetCoap = this.el.querySelector("#btn-set-coap");
    this.btnAddSensor = this.el.querySelector("#btn-add-sensor");
    this.btnUpdateSensor = this.el.querySelector("#btn-update-sensor");
    this.btnRemoveSensor = this.el.querySelector("#btn-remove-sensor");
    this.btnListSensors = this.el.querySelector("#btn-list-sensors");
    this.terminal = this.el.querySelector("#serial-terminal");

    this.toggleButtons = [
      this.btnSetWifi,
      this.btnSetCoap,
      this.btnAddSensor,
      this.btnUpdateSensor,
      this.btnRemoveSensor,
      this.btnListSensors,
    ];

    this.btnConnect.addEventListener("click", () => this.connect());
    this.btnDisconnect.addEventListener("click", () => this.disconnect());
    this.btnSetWifi.addEventListener("click", () => {
      const ssid = this.el.querySelector("#wifi-ssid").value;
      const password = this.el.querySelector("#wifi-pass").value;
      this.setWifi(ssid, password);
    });
    this.btnSetCoap.addEventListener("click", () => {
      const host = this.el.querySelector("#coap-host").value;
      const port = parseInt(this.el.querySelector("#coap-port").value || "5683");
      this.setCoap(host, port);
    });
    this.btnAddSensor.addEventListener("click", () => this.addSensor(this.readSensorForm()));
    this.btnUpdateSensor.addEventListener("click", () =>
      this.updateSensor(this.readSensorForm()),
    );
    this.btnRemoveSensor.addEventListener("click", () => {
      const id = parseInt(this.el.querySelector("#sensor-id").value);
      this.removeSensor(id);
    });
    this.btnListSensors.addEventListener("click", () => this.listSensors());
  },

  readSensorForm() {
    return {
      id: parseInt(this.el.querySelector("#sensor-id").value),
      pin: parseInt(this.el.querySelector("#sensor-pin").value),
      type: this.el.querySelector("#sensor-type").value,
      precision: parseFloat(this.el.querySelector("#sensor-precision").value || "1.0"),
      interval: parseInt(this.el.querySelector("#sensor-interval").value || "10000"),
    };
  },

  destroyed() {
    this.disconnect();
  },

  log(msg) {
    this.terminal.textContent += msg + "\n";
    this.terminal.scrollTop = this.terminal.scrollHeight;
  },

  async sendCommand(command) {
    if (!this.writer) return;
    const data = JSON.stringify(command) + "\n";
    const encoder = new TextEncoder();
    await this.writer.write(encoder.encode(data));
    this.log("-> " + data.trim());
  },

  setWifi(ssid, password) {
    return this.sendCommand({
      command: "wifi",
      data: { action: "set", ssid, password },
    });
  },

  setCoap(host, port) {
    return this.sendCommand({
      command: "coap",
      data: { action: "set", host, port },
    });
  },

  addSensor({ id, pin, type, precision, interval }) {
    return this.sendCommand({
      command: "sensor",
      data: { action: "add", id, pin, type, precision, interval },
    });
  },

  updateSensor({ id, pin, type, precision, interval }) {
    return this.sendCommand({
      command: "sensor",
      data: { action: "update", id, pin, type, precision, interval },
    });
  },

  removeSensor(id) {
    return this.sendCommand({
      command: "sensor",
      data: { action: "remove", id },
    });
  },

  listSensors() {
    return this.sendCommand({
      command: "sensor",
      data: { action: "list" },
    });
  },

  async connect() {
    try {
      this.port = await navigator.serial.requestPort();
      await this.port.open({ baudRate: 115200 });
      this.log("Connected to serial port at 115200");

      this.btnConnect.disabled = true;
      this.btnDisconnect.disabled = false;
      this.toggleButtons.forEach((btn) => (btn.disabled = false));

      this.keepReading = true;
      this.readLoop();
    } catch (e) {
      console.log(e);
      this.log("Connection failed: " + e.message);
    }
  },

  async disconnect() {
    this.keepReading = false;
    if (this.reader) {
      await this.reader.cancel().catch(() => {});
    }
    if (this.writer) {
      this.writer.releaseLock();
    }
    if (this.port) {
      await this.port.close().catch((e) => console.log(e));
    }
    this.log("Disconnected");
    this.btnConnect.disabled = false;
    this.btnDisconnect.disabled = true;
    this.toggleButtons.forEach((btn) => (btn.disabled = true));
  },

  async readLoop() {
    const decoder = new TextDecoderStream();
    this.port.readable.pipeTo(decoder.writable);
    const inputStream = decoder.readable;
    this.reader = inputStream.getReader();
    this.writer = this.port.writable.getWriter();

    let buffer = "";

    try {
      while (this.keepReading) {
        const { value, done } = await this.reader.read();
        if (done) break;
        if (value) {
          buffer += value;
          let lines = buffer.split("\n");
          buffer = lines.pop();
          for (let line of lines) {
            if (line.trim().length > 0) this.log("<- " + line.trim());
          }
        }
      }
    } catch (e) {
      this.log("Read error: " + e.message);
    } finally {
      this.reader.releaseLock();
    }
  },
};
