defmodule LiveMetricsWeb.DeviceSetupLive do
  @moduledoc """
  Configures a node over Web Serial and keeps its sensors in sync with the database.

  Sensors are saved first (the database assigns the id) and then pushed to the node through
  the `WebSerialHook`, which runs the commands one by one and reports back the sensors the
  node actually has, so every row shows whether both sides match.
  """
  use LiveMetricsWeb, :live_view

  alias LiveMetrics.Models.NodeSensorConfig

  # Reference wiring for the recommended sensors. Analog sensors must use ADC1 pins
  # (WiFi disables ADC2). value = raw * precision + offset, where raw is the driver
  # reading: 12-bit ADC (0..4095) for analog, physical units for digital drivers.
  @sensor_presets [
    %{
      key: "lm35",
      label: "LM35 temperature (°C)",
      driver: "analog",
      pin: 34,
      type: "temperature",
      precision: 0.0806,
      offset: 0.0,
      interval: 10_000
    },
    %{
      key: "ldr",
      label: "LDR light (%)",
      driver: "analog",
      pin: 35,
      type: "light",
      precision: 0.02442,
      offset: 0.0,
      interval: 10_000
    },
    %{
      # Calibrated with dry raw ~3000 (0%) and in-water raw ~1300 (100%)
      key: "soil",
      label: "Capacitive soil moisture (%)",
      driver: "analog",
      pin: 32,
      type: "soil_moisture",
      precision: -0.058824,
      offset: 176.47,
      interval: 30_000
    },
    %{
      key: "potentiometer",
      label: "Potentiometer (raw)",
      driver: "analog",
      pin: 33,
      type: "simulated",
      precision: 1.0,
      offset: 0.0,
      interval: 5_000
    },
    %{
      key: "dht22_temp",
      label: "DHT22 air temperature (°C)",
      driver: "dht22_temp",
      pin: 27,
      type: "air_temperature",
      precision: 1.0,
      offset: 0.0,
      interval: 10_000
    },
    %{
      key: "dht22_hum",
      label: "DHT22 air humidity (%)",
      driver: "dht22_hum",
      pin: 27,
      type: "air_humidity",
      precision: 1.0,
      offset: 0.0,
      interval: 10_000
    },
    %{
      key: "ds18b20",
      label: "DS18B20 temperature (°C)",
      driver: "ds18b20",
      pin: 26,
      type: "water_temperature",
      precision: 1.0,
      offset: 0.0,
      interval: 10_000
    }
  ]

  @driver_labels %{
    "analog" => "Analog (raw ADC 0–4095)",
    "dht22_temp" => "DHT22 temperature (°C)",
    "dht22_hum" => "DHT22 humidity (%)",
    "ds18b20" => "DS18B20 temperature (°C)"
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Device setup")
      |> assign(:serial_supported?, true)
      |> assign(:connected?, false)
      |> assign(:mac, nil)
      |> assign(:node_sensors, nil)
      |> assign(:orphans, [])
      |> assign(:busy?, false)
      |> assign(:editing, nil)
      |> assign(:configs_count, 0)
      |> assign(:sensor_presets, @sensor_presets)
      |> assign(:driver_options, Enum.map(NodeSensorConfig.drivers(), &{@driver_labels[&1], &1}))
      |> stream(:configs, [])
      |> assign_form(%NodeSensorConfig{})

    {:ok, socket}
  end

  # --- Serial transport events (from WebSerialHook) ---

  @impl true
  def handle_event("serial_unsupported", _params, socket) do
    {:noreply, assign(socket, :serial_supported?, false)}
  end

  def handle_event("serial_connected", _params, socket) do
    {:noreply, socket |> clear_flash() |> assign(:connected?, true)}
  end

  def handle_event("serial_disconnected", %{"message" => message}, socket) do
    {:noreply,
     socket
     |> assign(connected?: false, mac: nil, node_sensors: nil, orphans: [], busy?: false)
     |> assign(:editing, nil)
     |> assign(:configs_count, 0)
     |> stream(:configs, [], reset: true)
     |> assign_form(%NodeSensorConfig{})
     |> put_flash(:info, message)}
  end

  def handle_event("node_identified", %{"mac" => mac}, socket) do
    {:noreply,
     socket
     |> assign(:mac, String.upcase(mac))
     |> assign_form(%NodeSensorConfig{})
     |> load_configs()}
  end

  def handle_event("node_error", %{"message" => message}, socket) do
    {:noreply, put_flash(socket, :error, "Could not identify the node: #{message}")}
  end

  def handle_event("node_sensors", %{"sensors" => sensors}, socket) do
    node_sensors = Map.new(sensors, &{&1["id"], &1})

    {:noreply,
     socket
     |> assign(:node_sensors, node_sensors)
     |> load_configs()}
  end

  def handle_event("serial_commands_done", %{"results" => results}, socket) do
    failed = Enum.reject(results, & &1["ok"])

    socket =
      case failed do
        [] ->
          socket

        _ ->
          details = Enum.map_join(failed, "; ", &describe_failure/1)
          put_flash(socket, :error, "The node rejected #{length(failed)} command(s): #{details}")
      end

    {:noreply, assign(socket, :busy?, false)}
  end

  # --- Sensor form ---

  def handle_event("apply_preset", %{"preset" => key}, socket) do
    case Enum.find(@sensor_presets, &(&1.key == key)) do
      nil ->
        {:noreply, socket}

      preset ->
        params =
          Map.merge(socket.assigns.form.params, %{
            "driver" => preset.driver,
            "pin" => preset.pin,
            "sensor_type" => preset.type,
            "precision" => preset.precision,
            "offset" => preset.offset,
            "interval_ms" => preset.interval
          })

        {:noreply, assign_form(socket, socket.assigns.editing || %NodeSensorConfig{}, params)}
    end
  end

  def handle_event("validate", %{"node_sensor_config" => params}, socket) do
    {:noreply,
     assign_form(socket, socket.assigns.editing || %NodeSensorConfig{}, params, :validate)}
  end

  def handle_event("save", %{"node_sensor_config" => params}, socket) do
    %{mac: mac, editing: editing} = socket.assigns

    result =
      if editing,
        do: NodeSensorConfig.update(editing, params),
        else: NodeSensorConfig.create(mac, params)

    case result do
      {:ok, config} ->
        {:noreply,
         socket
         |> assign(:editing, nil)
         |> assign_form(%NodeSensorConfig{})
         |> load_configs()
         |> push_commands([
           NodeSensorConfig.to_serial_command(config, node_action(socket, config))
         ])
         |> put_flash(:info, "Sensor ##{config.id} saved, sending it to the node…")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    config = NodeSensorConfig.get_by_mac!(socket.assigns.mac, id)

    {:noreply,
     socket
     |> assign(:editing, config)
     |> assign_form(config)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> assign(:editing, nil) |> assign_form(%NodeSensorConfig{})}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    config = NodeSensorConfig.get_by_mac!(socket.assigns.mac, id)
    {:ok, _} = NodeSensorConfig.delete(config)

    commands =
      if on_node?(socket, config.id),
        do: [NodeSensorConfig.remove_serial_command(config.id)],
        else: []

    {:noreply,
     socket
     |> maybe_cancel_edit(config.id)
     |> load_configs()
     |> push_commands(commands)
     |> put_flash(:info, "Sensor ##{config.id} deleted")}
  end

  def handle_event("delete_all", _params, socket) do
    mac = socket.assigns.mac
    db_ids = Enum.map(NodeSensorConfig.list_by_mac(mac), & &1.id)
    node_ids = Map.keys(socket.assigns.node_sensors || %{})
    count = NodeSensorConfig.delete_all_by_mac(mac)

    commands =
      (db_ids ++ node_ids)
      |> Enum.uniq()
      |> Enum.filter(&on_node?(socket, &1))
      |> Enum.map(&NodeSensorConfig.remove_serial_command/1)

    {:noreply,
     socket
     |> assign(:editing, nil)
     |> assign_form(%NodeSensorConfig{})
     |> load_configs()
     |> push_commands(commands)
     |> put_flash(
       :info,
       "Deleted #{count} sensor(s) from the database and #{length(commands)} from the node"
     )}
  end

  def handle_event("sync_all", _params, socket) do
    commands =
      socket.assigns.mac
      |> NodeSensorConfig.list_by_mac()
      |> Enum.reject(&(sync_status(socket, &1) == :synced))
      |> Enum.map(&NodeSensorConfig.to_serial_command(&1, node_action(socket, &1)))

    {:noreply, push_commands(socket, commands)}
  end

  def handle_event("remove_orphan", %{"id" => id}, socket) do
    {:noreply,
     push_commands(socket, [NodeSensorConfig.remove_serial_command(String.to_integer(id))])}
  end

  # --- Helpers ---

  defp assign_form(socket, config, params \\ %{}, action \\ nil) do
    changeset =
      %{config | mac: socket.assigns[:mac] || config.mac}
      |> NodeSensorConfig.changeset(params)
      |> Map.put(:action, action)

    assign(socket, :form, to_form(changeset))
  end

  defp load_configs(%{assigns: %{mac: nil}} = socket), do: socket

  defp load_configs(socket) do
    configs = NodeSensorConfig.list_by_mac(socket.assigns.mac)
    db_ids = MapSet.new(configs, & &1.id)

    orphans =
      (socket.assigns.node_sensors || %{})
      |> Map.values()
      |> Enum.reject(&MapSet.member?(db_ids, &1["id"]))
      |> Enum.sort_by(& &1["id"])

    rows = Enum.map(configs, &%{id: &1.id, config: &1, status: sync_status(socket, &1)})

    socket
    |> assign(:configs_count, length(configs))
    |> assign(:orphans, orphans)
    |> stream(:configs, rows, reset: true)
  end

  defp sync_status(%{assigns: %{node_sensors: nil}}, _config), do: :unknown

  defp sync_status(socket, config) do
    NodeSensorConfig.sync_status(config, socket.assigns.node_sensors[config.id])
  end

  defp on_node?(socket, id), do: Map.has_key?(socket.assigns.node_sensors || %{}, id)

  defp node_action(socket, config), do: if(on_node?(socket, config.id), do: "update", else: "add")

  defp push_commands(socket, []), do: socket

  defp push_commands(socket, commands) do
    socket
    |> assign(:busy?, true)
    |> push_event("serial_commands", %{commands: commands})
  end

  defp maybe_cancel_edit(%{assigns: %{editing: %{id: id}}} = socket, id) do
    socket |> assign(:editing, nil) |> assign_form(%NodeSensorConfig{})
  end

  defp maybe_cancel_edit(socket, _id), do: socket

  defp describe_failure(%{"command" => %{"data" => data}, "message" => message}) do
    "#{data["action"]} ##{data["id"]} (#{message})"
  end

  defp describe_failure(%{"message" => message}), do: message

  defp format_number(value) when is_float(value) do
    value |> Float.round(6) |> :erlang.float_to_binary([:compact, decimals: 6])
  end

  defp format_number(value), do: to_string(value)

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="device-setup" class="space-y-6" phx-hook="WebSerialHook">
        <div class="flex flex-wrap items-center justify-between gap-4">
          <div class="flex items-center gap-3">
            <.button navigate={~p"/devices"} class="btn btn-ghost btn-sm" id="back-to-devices">
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Devices
            </.button>
            <div>
              <h1 class="text-3xl font-bold text-primary">Device setup</h1>
              <p class="text-sm text-base-content/60">
                Connect a node over USB, then manage its sensors. Changes are saved here and sent to the node.
              </p>
            </div>
          </div>
        </div>

        <%!-- Connection --%>
        <section
          id="connection-card"
          class={[
            "rounded-box border p-4 flex flex-wrap items-center justify-between gap-4 transition-colors",
            if(@connected?,
              do: "border-success/40 bg-success/5",
              else: "border-base-300 bg-base-200"
            )
          ]}
        >
          <div class="flex items-center gap-3">
            <span class={[
              "relative flex h-3 w-3",
              !@connected? && "opacity-40"
            ]}>
              <span
                :if={@connected?}
                class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-60"
              >
              </span>
              <span class={[
                "relative inline-flex rounded-full h-3 w-3",
                if(@connected?, do: "bg-success", else: "bg-base-content")
              ]}>
              </span>
            </span>
            <div class="leading-tight">
              <p id="connection-status" class="font-semibold">
                <%= cond do %>
                  <% not @serial_supported? -> %>
                    Web Serial not supported in this browser
                  <% @connected? and @mac -> %>
                    Connected
                  <% @connected? -> %>
                    Connected · identifying node…
                  <% true -> %>
                    Not connected
                <% end %>
              </p>
              <p :if={@mac} id="node-mac" class="font-mono text-xs text-base-content/60">{@mac}</p>
            </div>
          </div>

          <div class="flex gap-2">
            <.button
              id="btn-connect"
              type="button"
              data-serial-action="connect"
              class="btn btn-primary btn-sm"
              disabled={@connected? or not @serial_supported?}
            >
              <.icon name="hero-bolt" class="w-4 h-4" /> Connect to device
            </.button>
            <.button
              id="btn-disconnect"
              type="button"
              data-serial-action="disconnect"
              class="btn btn-ghost btn-sm"
              disabled={not @connected?}
            >
              Disconnect
            </.button>
          </div>
        </section>

        <%!-- WiFi / CoAP: handled in the browser so the WiFi password never reaches the server --%>
        <div
          id="network-panel"
          data-serial-panel
          phx-update="ignore"
          class="grid grid-cols-1 md:grid-cols-2 gap-4"
        >
          <div class="card bg-base-200 p-4 space-y-2">
            <h2 class="font-bold flex items-center gap-2">
              <.icon name="hero-wifi" class="w-4 h-4 text-secondary" /> WiFi
            </h2>
            <input
              type="text"
              id="wifi-ssid"
              placeholder="SSID"
              autocomplete="off"
              class="input input-bordered input-sm w-full"
            />
            <input
              type="password"
              id="wifi-pass"
              placeholder="Password"
              autocomplete="new-password"
              class="input input-bordered input-sm w-full"
            />
            <.button
              id="btn-set-wifi"
              type="button"
              data-serial-action="set-wifi"
              class="btn btn-sm btn-secondary w-full"
              disabled
            >
              Send WiFi to node
            </.button>
          </div>

          <div class="card bg-base-200 p-4 space-y-2">
            <h2 class="font-bold flex items-center gap-2">
              <.icon name="hero-server-stack" class="w-4 h-4 text-secondary" /> CoAP server
            </h2>
            <input
              type="text"
              id="coap-host"
              placeholder="Host IP (e.g. 192.168.1.100)"
              class="input input-bordered input-sm w-full"
            />
            <input
              type="number"
              id="coap-port"
              placeholder="Port (default 5683)"
              value="5683"
              class="input input-bordered input-sm w-full"
            />
            <.button
              id="btn-set-coap"
              type="button"
              data-serial-action="set-coap"
              class="btn btn-sm btn-secondary w-full"
              disabled
            >
              Send CoAP target to node
            </.button>
          </div>
        </div>

        <%!-- Sensors --%>
        <section id="sensors-card" class="card bg-base-200 p-4 space-y-4">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h2 class="font-bold text-lg flex items-center gap-2">
                <.icon name="hero-signal" class="w-5 h-5 text-accent" /> Sensors
                <span :if={@mac} class="badge badge-sm badge-ghost">{@configs_count}</span>
                <span
                  :if={@busy?}
                  id="sync-busy"
                  class="loading loading-spinner loading-xs text-primary"
                >
                </span>
              </h2>
              <p class="text-xs text-base-content/60">
                Value sent = driver reading × precision + offset (analog reading is raw ADC 0–4095)
              </p>
            </div>
            <div :if={@mac} class="flex gap-2">
              <.button
                id="btn-sync-all"
                type="button"
                phx-click="sync_all"
                class="btn btn-sm btn-outline"
                disabled={@busy? or @configs_count == 0}
              >
                <.icon name="hero-arrow-path" class="w-4 h-4" /> Send all to node
              </.button>
              <.button
                id="btn-delete-all"
                type="button"
                phx-click="delete_all"
                data-confirm="Delete ALL sensors of this node from the database and from the node?"
                class="btn btn-sm btn-error btn-outline"
                disabled={@busy? or (@configs_count == 0 and @orphans == [])}
              >
                <.icon name="hero-trash" class="w-4 h-4" /> Delete all
              </.button>
            </div>
          </div>

          <div
            :if={is_nil(@mac)}
            id="sensors-locked"
            class="rounded-box border border-dashed border-base-300 p-8 text-center text-base-content/60"
          >
            <.icon name="hero-cpu-chip" class="w-10 h-10 mx-auto mb-2 opacity-40" />
            <p>Connect a node to see and edit its sensors.</p>
          </div>

          <div :if={@mac} class="space-y-4">
            <div class="rounded-box bg-base-100 border border-base-300 p-4 space-y-3">
              <div class="flex flex-wrap items-end justify-between gap-2">
                <h3 class="font-semibold">
                  {if @editing, do: "Edit sensor ##{@editing.id}", else: "New sensor"}
                </h3>
                <form id="preset-form" phx-change="apply_preset" class="w-full md:w-72">
                  <.input
                    type="select"
                    id="sensor-preset"
                    name="preset"
                    label="Fill from preset"
                    prompt="Choose a preset…"
                    value=""
                    options={Enum.map(@sensor_presets, &{&1.label, &1.key})}
                    class="select select-sm select-bordered w-full"
                  />
                </form>
              </div>

              <.form
                for={@form}
                id="sensor-form"
                phx-change="validate"
                phx-submit="save"
                class="space-y-3"
              >
                <div class="grid grid-cols-2 md:grid-cols-6 gap-3">
                  <.input
                    field={@form[:driver]}
                    type="select"
                    label="Driver"
                    options={@driver_options}
                    class="select select-sm select-bordered w-full"
                  />
                  <.input
                    field={@form[:pin]}
                    type="number"
                    label="Pin (GPIO)"
                    min="0"
                    max="39"
                    class="input input-sm input-bordered w-full"
                  />
                  <.input
                    field={@form[:sensor_type]}
                    type="text"
                    label="Type"
                    placeholder="soil_moisture"
                    autocomplete="off"
                    class="input input-sm input-bordered w-full font-mono"
                  />
                  <.input
                    field={@form[:precision]}
                    type="number"
                    step="any"
                    label="Precision"
                    class="input input-sm input-bordered w-full"
                  />
                  <.input
                    field={@form[:offset]}
                    type="number"
                    step="any"
                    label="Offset"
                    class="input input-sm input-bordered w-full"
                  />
                  <.input
                    field={@form[:interval_ms]}
                    type="number"
                    label="Interval (ms)"
                    min="500"
                    class="input input-sm input-bordered w-full"
                  />
                </div>
                <div class="flex justify-end gap-2">
                  <.button
                    :if={@editing}
                    id="btn-cancel-edit"
                    type="button"
                    phx-click="cancel_edit"
                    class="btn btn-sm btn-ghost"
                  >
                    Cancel
                  </.button>
                  <.button
                    id="btn-save-sensor"
                    type="submit"
                    class="btn btn-sm btn-primary"
                    disabled={@busy?}
                    phx-disable-with="Saving…"
                  >
                    <.icon name="hero-check" class="w-4 h-4" />
                    {if @editing, do: "Save and send to node", else: "Add and send to node"}
                  </.button>
                </div>
              </.form>
            </div>

            <div
              :if={@configs_count == 0}
              id="sensor-configs-empty"
              class="rounded-box border border-dashed border-base-300 p-6 text-center text-sm text-base-content/50"
            >
              No sensors saved for this node yet.
            </div>
            <div class={[
              "overflow-x-auto rounded-box border border-base-300 bg-base-100",
              @configs_count == 0 && "hidden"
            ]}>
              <.table
                id="sensor-configs"
                rows={@streams.configs}
                row_item={fn {_dom_id, row} -> row end}
              >
                <:col :let={row} label="ID"><span class="font-mono">#{row.id}</span></:col>
                <:col :let={row} label="Type">
                  <span class="font-mono">{row.config.sensor_type}</span>
                </:col>
                <:col :let={row} label="Driver">
                  <span class="text-xs">{row.config.driver}</span>
                </:col>
                <:col :let={row} label="Pin"><span class="font-mono">{row.config.pin}</span></:col>
                <:col :let={row} label="Precision">
                  <span class="font-mono tabular-nums">{format_number(row.config.precision)}</span>
                </:col>
                <:col :let={row} label="Offset">
                  <span class="font-mono tabular-nums">{format_number(row.config.offset)}</span>
                </:col>
                <:col :let={row} label="Interval">
                  <span class="font-mono tabular-nums whitespace-nowrap">
                    {row.config.interval_ms} ms
                  </span>
                </:col>
                <:col :let={row} label="Node">
                  <.sync_badge status={row.status} id={"sync-status-#{row.id}"} />
                </:col>
                <:action :let={row}>
                  <.button
                    id={"edit-sensor-#{row.id}"}
                    type="button"
                    phx-click="edit"
                    phx-value-id={row.id}
                    class="btn btn-ghost btn-xs"
                    disabled={@busy?}
                  >
                    <.icon name="hero-pencil-square" class="w-4 h-4" />
                  </.button>
                  <.button
                    id={"delete-sensor-#{row.id}"}
                    type="button"
                    phx-click="delete"
                    phx-value-id={row.id}
                    data-confirm={"Delete sensor ##{row.id} from the database and the node?"}
                    class="btn btn-ghost btn-xs text-error"
                    disabled={@busy?}
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </.button>
                </:action>
              </.table>
            </div>

            <div
              :if={@orphans != []}
              id="node-orphans"
              class="rounded-box border border-warning/40 bg-warning/5 p-4 space-y-2"
            >
              <p class="text-sm font-semibold flex items-center gap-2">
                <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-warning" />
                On the node but not in the database
              </p>
              <div
                :for={sensor <- @orphans}
                id={"orphan-#{sensor["id"]}"}
                class="flex items-center justify-between gap-2 text-sm"
              >
                <span class="font-mono">
                  #{sensor["id"]} · {sensor["type"]} · {sensor["driver"]} · pin {sensor["pin"]}
                </span>
                <.button
                  id={"remove-orphan-#{sensor["id"]}"}
                  type="button"
                  phx-click="remove_orphan"
                  phx-value-id={sensor["id"]}
                  class="btn btn-xs btn-outline btn-warning"
                  disabled={@busy?}
                >
                  Remove from node
                </.button>
              </div>
            </div>
          </div>
        </section>

        <%!-- Terminal --%>
        <section class="card bg-base-200 p-4">
          <div class="flex items-center justify-between mb-2">
            <h2 class="font-bold flex items-center gap-2">
              <.icon name="hero-command-line" class="w-4 h-4" /> Terminal
            </h2>
            <.button
              id="btn-clear-terminal"
              type="button"
              data-serial-action="clear-terminal"
              class="btn btn-ghost btn-xs"
            >
              Clear
            </.button>
          </div>
          <pre
            id="serial-terminal"
            phx-update="ignore"
            class="bg-black text-green-400 p-3 h-56 overflow-y-auto text-xs rounded font-mono whitespace-pre-wrap break-all"
          ></pre>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :status, :atom, required: true
  attr :id, :string, required: true

  defp sync_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% :synced -> %>
        <span id={@id} class="badge badge-sm badge-success badge-soft gap-1">
          <.icon name="hero-check-circle-mini" class="w-3.5 h-3.5" /> Synced
        </span>
      <% :differs -> %>
        <span id={@id} class="badge badge-sm badge-warning badge-soft gap-1">
          <.icon name="hero-exclamation-triangle-mini" class="w-3.5 h-3.5" /> Differs
        </span>
      <% :missing -> %>
        <span id={@id} class="badge badge-sm badge-error badge-soft gap-1">
          <.icon name="hero-x-circle-mini" class="w-3.5 h-3.5" /> Not on node
        </span>
      <% :unknown -> %>
        <span id={@id} class="badge badge-sm badge-ghost gap-1">
          <.icon name="hero-question-mark-circle-mini" class="w-3.5 h-3.5" /> Unknown
        </span>
    <% end %>
    """
  end
end
