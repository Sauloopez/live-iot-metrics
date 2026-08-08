defmodule LiveMetricsWeb.Components.NodeModal do
  alias LiveMetrics.Models.{Nodes, Sensor}
  use LiveMetricsWeb, :live_component

  @impl true
  def update(%{node_id: node_id} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:node, Nodes.find_with_sensors(node_id))}
  end

  attr :node_id, :any, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <dialog class="modal modal-open">
      <div class="modal-box max-w-3xl">
        <h3 class="font-bold text-lg">
          <.icon name="hero-cpu-chip" class="w-5 h-5 inline-block mr-1 text-secondary" />
          {@node.name}
        </h3>
        <p class="font-mono text-sm text-base-content/60 mb-4">{@node.mac}</p>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm bg-base-200 rounded-box p-4 mb-6">
          <div class="flex justify-between">
            <span class="text-base-content/60">Created</span>
            <span class="font-mono">{Calendar.strftime(@node.inserted_at, "%Y-%m-%d %H:%M")}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/60">Description</span>
            <span>{@node.description || "-"}</span>
          </div>
        </div>

        <div class="divider">Sensors</div>

        <%= if Enum.empty?(@node.sensors) do %>
          <p class="text-center text-base-content/60 py-4">This node has no sensors.</p>
        <% else %>
          <.table id="node-modal-sensors" rows={Enum.sort_by(@node.sensors, & &1.node_sensor_id)}>
            <:col :let={sensor} label="ID">{sensor.node_sensor_id}</:col>
            <:col :let={sensor} label="Type">
              <.icon name="hero-signal" class="w-4 h-4 inline-block mr-1 text-accent" />
              <span class="capitalize">{sensor.sensor_type}</span>
            </:col>
            <:col :let={sensor} label="Precision">{sensor.precision}</:col>
            <:col :let={sensor} label="Status">
              <%= if sensor.active do %>
                <span class="badge badge-success badge-outline badge-sm">Active</span>
              <% else %>
                <span class="badge badge-ghost badge-sm">
                  Inactive since {Calendar.strftime(sensor.inactivated_at, "%Y-%m-%d %H:%M")}
                </span>
              <% end %>
            </:col>
            <:action :let={sensor}>
              <%= if sensor.active do %>
                <button
                  class="btn btn-xs btn-error btn-outline"
                  phx-click="toggle_sensor"
                  phx-value-sensor-id={sensor.id}
                  phx-target={@myself}
                  data-confirm="Stop recording data from this sensor?"
                >
                  Deactivate
                </button>
              <% else %>
                <button
                  class="btn btn-xs btn-success btn-outline"
                  phx-click="toggle_sensor"
                  phx-value-sensor-id={sensor.id}
                  phx-target={@myself}
                >
                  Activate
                </button>
              <% end %>
            </:action>
          </.table>
        <% end %>

        <div class="modal-action mt-6">
          <button type="button" class="btn" phx-click="close_node_modal">Close</button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop" phx-click="close_node_modal">
        <button>close</button>
      </form>
    </dialog>
    """
  end

  @impl true
  def handle_event("toggle_sensor", %{"sensor-id" => sensor_id}, socket) do
    sensor = Enum.find(socket.assigns.node.sensors, &(&1.id == sensor_id))

    result = if sensor.active, do: Sensor.deactivate(sensor), else: Sensor.activate(sensor)

    case result do
      {:ok, updated_sensor} ->
        sensors =
          Enum.map(socket.assigns.node.sensors, fn
            s when s.id == sensor_id -> updated_sensor
            s -> s
          end)

        {:noreply, assign(socket, :node, %{socket.assigns.node | sensors: sensors})}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end
end
