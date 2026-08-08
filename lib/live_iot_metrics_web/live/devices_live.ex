defmodule LiveMetricsWeb.DevicesLive do
  use LiveMetricsWeb, :live_view

  alias LiveMetrics.Models.Nodes
  alias LiveMetricsWeb.Components.NodeModal

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:managing_node_id, nil)
      |> assign(:show_config_modal, false)
      |> load_nodes()

    {:ok, socket}
  end

  defp load_nodes(socket) do
    assign(socket, :nodes, Nodes.find_all())
  end

  @impl true
  def handle_event("manage_node", %{"id" => id}, socket) do
    {:noreply, assign(socket, :managing_node_id, id)}
  end

  def handle_event("close_node_modal", _, socket) do
    {:noreply, socket |> assign(:managing_node_id, nil) |> load_nodes()}
  end

  def handle_event("open_config_modal", _, socket) do
    {:noreply, assign(socket, :show_config_modal, true)}
  end

  def handle_event("close_config_modal", _, socket) do
    {:noreply, assign(socket, :show_config_modal, false)}
  end

  defp sensor_counts_by_type(sensors) do
    sensors
    |> Enum.group_by(& &1.sensor_type)
    |> Enum.map(fn {type, list} -> {type, length(list)} end)
    |> Enum.sort_by(fn {type, _count} -> type end)
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
          <%= if Enum.empty?(@nodes) do %>
            <div class="text-center py-12 text-base-content/70">
              <.icon name="hero-cpu-chip" class="w-12 h-12 mx-auto mb-4 opacity-50" />
              <p>No devices found.</p>
            </div>
          <% else %>
            <.table id="nodes-table" rows={@nodes}>
              <:col :let={node} label="Name">{node.name}</:col>
              <:col :let={node} label="MAC Address">
                <span class="font-mono text-sm">{node.mac}</span>
              </:col>
              <:col :let={node} label="Created">
                <span class="font-mono text-sm">
                  {Calendar.strftime(node.inserted_at, "%Y-%m-%d %H:%M")}
                </span>
              </:col>
              <:col :let={node} label="Sensors">
                <div class="flex flex-wrap gap-1">
                  <%= if Enum.empty?(node.sensors) do %>
                    <span class="text-base-content/50 italic text-sm">None</span>
                  <% else %>
                    <%= for {type, count} <- sensor_counts_by_type(node.sensors) do %>
                      <span class="badge badge-outline badge-sm capitalize">{type}: {count}</span>
                    <% end %>
                  <% end %>
                </div>
              </:col>
              <:action :let={node}>
                <button
                  class="btn btn-sm btn-ghost"
                  phx-click="manage_node"
                  phx-value-id={node.id}
                >
                  <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Manage
                </button>
              </:action>
            </.table>
          <% end %>
        </div>

        <%= if @managing_node_id do %>
          <.live_component id="node-modal" module={NodeModal} node_id={@managing_node_id} />
        <% end %>
      </div>

      <%= if @show_config_modal do %>
        <dialog class="modal modal-open">
          <div
            class="modal-box max-w-4xl"
            id="web-serial-container"
            phx-hook="WebSerialHook"
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
              <h4 class="font-bold mb-2">Sensor Configuration</h4>
              <div class="grid grid-cols-2 md:grid-cols-5 gap-2 mb-2">
                <.input
                  type="number"
                  id="sensor-id"
                  name="sensor-id"
                  label="ID"
                  value=""
                  class="input input-sm input-bordered w-full"
                />
                <.input
                  type="number"
                  id="sensor-pin"
                  name="sensor-pin"
                  label="Pin"
                  value=""
                  class="input input-sm input-bordered w-full"
                />
                <.input
                  type="text"
                  id="sensor-type"
                  name="sensor-type"
                  label="Type"
                  value=""
                  class="input input-sm input-bordered w-full"
                />
                <.input
                  type="number"
                  step="0.1"
                  id="sensor-precision"
                  name="sensor-precision"
                  label="Precision"
                  value="1.0"
                  class="input input-sm input-bordered w-full"
                />
                <.input
                  type="number"
                  id="sensor-interval"
                  name="sensor-interval"
                  label="Interval Reading (ms)"
                  value="10000"
                  class="input input-sm input-bordered w-full"
                />
              </div>
              <div class="flex flex-wrap gap-2">
                <button id="btn-add-sensor" class="btn btn-sm btn-secondary" disabled>
                  Add
                </button>
                <button id="btn-update-sensor" class="btn btn-sm btn-secondary" disabled>
                  Update
                </button>
                <button id="btn-remove-sensor" class="btn btn-sm btn-error btn-outline" disabled>
                  Remove
                </button>
                <button id="btn-list-sensors" class="btn btn-sm btn-ghost" disabled>
                  List Sensors
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
        </dialog>
      <% end %>
    </LiveMetricsWeb.Layouts.app>
    """
  end
end
