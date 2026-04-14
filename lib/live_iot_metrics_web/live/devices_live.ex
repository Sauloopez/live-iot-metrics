defmodule LiveMetricsWeb.DevicesLive do
  use LiveMetricsWeb, :live_view

  alias LiveMetrics.Nodes
  alias LiveMetrics.Area
  alias LiveMetrics.Sensor
  alias LiveMetrics.Repo
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    areas = Repo.all(Area)

    socket =
      socket
      |> assign(:areas, areas)
      |> assign(:editing_node, nil)
      |> assign(:show_config_modal, false)
      |> load_nodes()

    {:ok, socket}
  end

  defp load_nodes(socket) do
    nodes = Repo.all(from n in Nodes, preload: [:area])
    assign(socket, :nodes, nodes)
  end

  @impl true
  def handle_event("edit_node", %{"id" => id}, socket) do
    node = Repo.get!(Nodes, id) |> Repo.preload([:area])
    changeset = Nodes.changeset(node, %{})

    sensors = Repo.all(from s in Sensor, where: s.node_id == ^id)

    socket =
      socket
      |> assign(:editing_node, node)
      |> assign(:sensors, sensors)
      |> assign(:form, to_form(changeset))

    {:noreply, socket}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :editing_node, nil)}
  end

  def handle_event("open_config_modal", _, socket) do
    {:noreply, assign(socket, :show_config_modal, true)}
  end

  def handle_event("close_config_modal", _, socket) do
    {:noreply, assign(socket, :show_config_modal, false)}
  end

  def handle_event("validate", %{"nodes" => params}, socket) do
    changeset =
      socket.assigns.editing_node
      |> Nodes.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"nodes" => params}, socket) do
    case socket.assigns.editing_node
         |> Nodes.changeset(params)
         |> Repo.update() do
      {:ok, _node} ->
        socket =
          socket
          |> put_flash(:info, "Device updated successfully")
          |> assign(:editing_node, nil)
          |> assign(:show_config_modal, false)
          |> load_nodes()

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp format_mac(nil), do: ""

  defp format_mac(mac) when is_binary(mac) do
    mac
    |> Base.encode16()
    |> to_charlist()
    |> Enum.chunk_every(2)
    |> Enum.join(":")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LiveMetricsWeb.Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div class="flex justify-between items-center">
          <h1 class="text-3xl font-bold text-primary">Devices</h1>
          <button class="btn btn-secondary btn-sm" phx-click="open_config_modal">
            <.icon name="hero-bolt" class="w-4 h-4 mr-2" /> Configure via USB
          </button>
        </div>

        <div class="bg-base-200 rounded-box p-6">
          <div class="overflow-x-auto">
            <table class="table table-zebra w-full">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>MAC Address</th>
                  <th>Area</th>
                  <th>Description</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for node <- @nodes do %>
                  <tr>
                    <td class="font-medium">{node.name}</td>
                    <td class="font-mono text-sm">{format_mac(node.mac)}</td>
                    <td>
                      <%= if node.area do %>
                        <div class="badge badge-primary">{node.area.name}</div>
                      <% else %>
                        <div class="badge badge-ghost">Unassigned</div>
                      <% end %>
                    </td>
                    <td class="truncate max-w-xs">{node.description || "-"}</td>
                    <td>
                      <button
                        class="btn btn-sm btn-ghost"
                        phx-click="edit_node"
                        phx-value-id={node.id}
                      >
                        <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>

            <%= if Enum.empty?(@nodes) do %>
              <div class="text-center py-12 text-base-content/70">
                <.icon name="hero-cpu-chip" class="w-12 h-12 mx-auto mb-4 opacity-50" />
                <p>No devices found.</p>
              </div>
            <% end %>
          </div>
        </div>

        <%= if @editing_node do %>
          <dialog class="modal modal-open">
            <div class="modal-box max-w-2xl">
              <h3 class="font-bold text-lg mb-4">Edit Device</h3>

              <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <.input field={@form[:name]} type="text" label="Name" required />
                  </div>

                  <div class="form-control">
                    <label class="label">
                      <span class="label-text">MAC Address (Read-only)</span>
                    </label>
                    <input
                      type="text"
                      value={format_mac(@editing_node.mac)}
                      class="input input-bordered w-full font-mono bg-base-200"
                      readonly
                      disabled
                    />
                  </div>

                  <div class="form-control md:col-span-2">
                    <label class="label">
                      <span class="label-text">Area</span>
                    </label>
                    <.input
                      field={@form[:area_id]}
                      type="select"
                      prompt="Select an area (optional)"
                      options={Enum.map(@areas, &{&1.name, &1.id})}
                    />
                  </div>

                  <div class="form-control md:col-span-2">
                    <.input field={@form[:description]} type="textarea" label="Description" />
                  </div>
                </div>

                <div class="divider">Sensors</div>

                <div class="bg-base-200 rounded-lg p-4 max-h-48 overflow-y-auto">
                  <%= if Enum.empty?(@sensors) do %>
                    <p class="text-center text-sm text-base-content/70 py-4">
                      No sensors detected for this device yet.
                    </p>
                  <% else %>
                    <table class="table table-sm">
                      <thead>
                        <tr>
                          <th>ID</th>
                          <th>Type</th>
                          <th>Precision</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for sensor <- @sensors do %>
                          <tr>
                            <td>{sensor.node_sensor_id}</td>
                            <td>
                              <div class="badge badge-outline">{sensor.sensor_type}</div>
                            </td>
                            <td>{sensor.precision}</td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  <% end %>
                </div>

                <div class="modal-action mt-6">
                  <button type="button" class="btn" phx-click="close_modal">Cancel</button>
                  <button type="submit" class="btn btn-primary" disabled={not @form.source.valid?}>
                    Save Changes
                  </button>
                </div>
              </.form>
            </div>
            <form method="dialog" class="modal-backdrop" phx-click="close_modal">
              <button>close</button>
            </form>
          </dialog>
        <% end %>
      </div>

      <%= if @show_config_modal do %>
        <dialog class="modal modal-open">
          <div
            class="modal-box max-w-3xl"
            id="web-serial-container"
            phx-hook=".WebSerial"
            phx-update="ignore"
          >
            <h3 class="font-bold text-lg mb-4">Configure Device via USB</h3>

            <div class="flex gap-4 mb-4">
              <button id="btn-connect" class="btn btn-primary">Connect to Device</button>
              <button id="btn-disconnect" class="btn btn-ghost" disabled>Disconnect</button>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div class="card bg-base-200 p-4">
                <h4 class="font-bold mb-2">WiFi Configuration</h4>
                <input
                  type="text"
                  id="wifi-ssid"
                  placeholder="SSID"
                  class="input input-bordered input-sm w-full mb-2"
                />
                <input
                  type="password"
                  id="wifi-pass"
                  placeholder="Password"
                  class="input input-bordered input-sm w-full mb-2"
                />
                <button id="btn-set-wifi" class="btn btn-sm btn-secondary w-full" disabled>
                  Set WiFi
                </button>
              </div>

              <div class="card bg-base-200 p-4">
                <h4 class="font-bold mb-2">CoAP Target</h4>
                <input
                  type="text"
                  id="coap-host"
                  placeholder="Host IP (e.g. 192.168.1.100)"
                  class="input input-bordered input-sm w-full mb-2"
                />
                <input
                  type="number"
                  id="coap-port"
                  placeholder="Port (default 5683)"
                  value="5683"
                  class="input input-bordered input-sm w-full mb-2"
                />
                <button id="btn-set-coap" class="btn btn-sm btn-secondary w-full" disabled>
                  Set CoAP
                </button>
              </div>
            </div>

            <div class="mt-4 card bg-base-200 p-4">
              <h4 class="font-bold mb-2">Terminal</h4>
              <pre
                id="serial-terminal"
                class="bg-black text-green-400 p-2 h-48 overflow-y-auto text-xs rounded font-mono"
              ></pre>
            </div>

            <div class="modal-action mt-6">
              <button type="button" class="btn" phx-click="close_config_modal">Close</button>
            </div>
          </div>
          <form method="dialog" class="modal-backdrop" phx-click="close_config_modal">
            <button>close</button>
          </form>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".WebSerial">
            export default {
              mounted() {
                this.port = null;
                this.reader = null;
                this.writer = null;
                this.keepReading = true;

                const btnConnect = this.el.querySelector("#btn-connect");
                const btnDisconnect = this.el.querySelector("#btn-disconnect");
                const btnSetWifi = this.el.querySelector("#btn-set-wifi");
                const btnSetCoap = this.el.querySelector("#btn-set-coap");
                const terminal = this.el.querySelector("#serial-terminal");

                const log = (msg) => {
                  terminal.textContent += msg + "\n";
                  terminal.scrollTop = terminal.scrollHeight;
                };

                const sendCommand = async (command) => {
                  if (!this.writer) return;
                  const data = JSON.stringify(command) + "\n";
                  const encoder = new TextEncoder();
                  await this.writer.write(encoder.encode(data));
                  log("-> " + data.trim());
                };

                btnConnect.addEventListener("click", async () => {
                  try {
                    this.port = await navigator.serial.requestPort();
                    await this.port.open({ baudRate: 115200 });
                    log("Connected to serial port at 115200");

                    btnConnect.disabled = true;
                    btnDisconnect.disabled = false;
                    btnSetWifi.disabled = false;
                    btnSetCoap.disabled = false;

                    this.keepReading = true;
                    this.readLoop();
                  } catch (e) {
                    console.log(e);
                    log("Connection failed: " + e.message);
                  }
                });

                btnDisconnect.addEventListener("click", async () => {
                  this.keepReading = false;
                  if (this.reader) {
                    await this.reader.cancel();
                  }
                  if (this.writer) {
                    this.writer.releaseLock();
                  }
                  if (this.port) {
                    await this.port.close();
                  }
                  log("Disconnected");
                  btnConnect.disabled = false;
                  btnDisconnect.disabled = true;
                  btnSetWifi.disabled = true;
                  btnSetCoap.disabled = true;
                });

                btnSetWifi.addEventListener("click", () => {
                  const ssid = this.el.querySelector("#wifi-ssid").value;
                  const pass = this.el.querySelector("#wifi-pass").value;
                  sendCommand({
                    command: "wifi",
                    data: { action: "set", ssid: ssid, password: pass }
                  });
                });

                btnSetCoap.addEventListener("click", () => {
                  const host = this.el.querySelector("#coap-host").value;
                  const port = parseInt(this.el.querySelector("#coap-port").value || "5683");
                  sendCommand({
                    command: "coap",
                    data: { action: "set", host: host, port: port }
                  });
                });

                this.readLoop = async () => {
                  const decoder = new TextDecoderStream();
                  const inputDone = this.port.readable.pipeTo(decoder.writable);
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
                          if (line.trim().length > 0) log("<- " + line.trim());
                        }
                      }
                    }
                  } catch (e) {
                    log("Read error: " + e.message);
                  } finally {
                    this.reader.releaseLock();
                  }
                };
              },
              destroyed() {
                this.keepReading = false;
                if (this.reader) {
                  this.reader.cancel().catch(() => {});
                }
                if (this.writer) {
                  this.writer.releaseLock();
                }
                if (this.port) {
                  this.port.close().catch((e) => {
                    console.log(e);
                  });
                }
              }
            }
          </script>
        </dialog>
      <% end %>
    </LiveMetricsWeb.Layouts.app>
    """
  end
end
