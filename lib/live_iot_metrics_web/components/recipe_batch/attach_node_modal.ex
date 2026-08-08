defmodule LiveMetricsWeb.Components.AttachNodeModal do
  alias LiveMetrics.Models.{Nodes, BatchSensor}
  use LiveMetricsWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:selected_node, fn -> nil end)
     |> assign_new(:error, fn -> nil end)}
  end

  attr :available_nodes, :list, required: true
  attr :property_ranges, :list, required: true
  attr :recipe_batch_id, :any, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <dialog class="modal modal-open">
      <div class="modal-box max-w-4xl">
        <h3 class="font-bold text-lg mb-4">Attach Node to Batch</h3>

        <div :if={@error} class="alert alert-error mb-4">
          <.icon name="hero-exclamation-circle" class="w-5 h-5" /> <span>{@error}</span>
        </div>

        <%= if Enum.empty?(@available_nodes) do %>
          <div class="alert alert-info">
            <.icon name="hero-information-circle" class="w-6 h-6" />
            <span>No available nodes. Every node is already tracked by an active batch.</span>
          </div>
          <div class="modal-action">
            <button type="button" class="btn" phx-click="close_attach_node">Close</button>
          </div>
        <% else %>
          <form phx-change="select_node" phx-target={@myself}>
            <div class="fieldset mb-4">
              <label for="attach-node-select">
                <span class="label mb-1">Node</span>
                <select id="attach-node-select" name="node_id" class="w-full select">
                  <option value="">Pick a node...</option>
                  <%= for node <- @available_nodes do %>
                    <option value={node.id} selected={@selected_node && @selected_node.id == node.id}>
                      {node.name} ({node.mac})
                    </option>
                  <% end %>
                </select>
              </label>
            </div>
          </form>

          <%= if @selected_node do %>
            <form phx-submit="attach" phx-target={@myself}>
              <%= if Enum.empty?(@selected_node.sensors) do %>
                <p class="text-center text-base-content/60 py-4">This node has no sensors.</p>
              <% else %>
                <.table
                  id="attach-node-sensors"
                  rows={@selected_node.sensors}
                  row_item={&{&1, matching_range(@property_ranges, &1.sensor_type)}}
                >
                  <:col :let={{sensor, range}} label="Track">
                    <input
                      type="checkbox"
                      name="sensor_ids[]"
                      value={sensor.id}
                      class="checkbox checkbox-primary"
                      checked={not is_nil(range)}
                      disabled={is_nil(range)}
                    />
                  </:col>
                  <:col :let={{sensor, _range}} label="Sensor Type">
                    <.icon name="hero-signal" class="w-4 h-4 inline-block mr-1 text-accent" />
                    <span class="capitalize">{sensor.sensor_type}</span>
                  </:col>
                  <:col :let={{sensor, _range}} label="Precision">{sensor.precision}</:col>
                  <:col :let={{_sensor, range}} label="Recipe Range">
                    <%= if range do %>
                      <span class="font-mono">{range.min_value} - {range.max_value}</span>
                    <% else %>
                      <span class="text-base-content/50 italic">No range in recipe</span>
                    <% end %>
                  </:col>
                </.table>
              <% end %>
              <div class="modal-action mt-6">
                <button type="button" class="btn" phx-click="close_attach_node">Cancel</button>
                <button
                  type="submit"
                  class="btn btn-primary"
                  disabled={Enum.empty?(@selected_node.sensors)}
                >
                  Attach Node
                </button>
              </div>
            </form>
          <% end %>
        <% end %>
      </div>
      <form method="dialog" class="modal-backdrop" phx-click="close_attach_node">
        <button>close</button>
      </form>
    </dialog>
    """
  end

  @impl true
  def handle_event("select_node", %{"node_id" => ""}, socket) do
    {:noreply, assign(socket, :selected_node, nil)}
  end

  def handle_event("select_node", %{"node_id" => node_id}, socket) do
    {:noreply, assign(socket, :selected_node, Nodes.find_with_sensors(node_id))}
  end

  @impl true
  def handle_event("attach", params, socket) do
    sensor_ids = Map.get(params, "sensor_ids", [])
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    sensors_by_id = Map.new(socket.assigns.selected_node.sensors, &{&1.id, &1})

    entries =
      sensor_ids
      |> Enum.map(&Map.get(sensors_by_id, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&{&1, matching_range(socket.assigns.property_ranges, &1.sensor_type)})
      |> Enum.filter(fn {_sensor, range} -> not is_nil(range) end)
      |> Enum.map(fn {sensor, range} ->
        %{
          sensor_id: sensor.id,
          recipe_batch_id: socket.assigns.recipe_batch_id,
          min_value: range.min_value,
          max_value: range.max_value,
          started_at: now
        }
      end)

    case entries do
      [] ->
        {:noreply,
         assign(socket, :error, "Select at least one sensor with a matching recipe range.")}

      entries ->
        case BatchSensor.create_many(entries) do
          {:ok, batch_sensors} ->
            send(self(), {:nodes_attached, batch_sensors})
            {:noreply, socket}

          {:error, changeset} ->
            {:noreply,
             assign(socket, :error, "Could not attach node: #{changeset_errors(changeset)}")}
        end
    end
  end

  defp matching_range(ranges, sensor_type) do
    Enum.find(ranges, &(&1.sensor_type == sensor_type))
  end

  defp changeset_errors(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end
end
