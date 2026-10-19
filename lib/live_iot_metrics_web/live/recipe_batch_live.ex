defmodule LiveMetricsWeb.RecipeBatchLive do
  alias Phoenix.PubSub
  alias LiveMetrics.Models.{RecipeBatch, BatchSensor, Nodes}
  alias LiveMetricsWeb.Components.{AttachNodeModal, NodeModal}
  use LiveMetricsWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _, socket) do
    if connected?(socket) do
      PubSub.subscribe(LiveMetrics.PubSub, "sensor_readings")
    end

    socket =
      socket
      |> assign(:recipe_batch_id, id)
      |> assign(:show_attach_node_modal, false)
      |> assign(:managing_node_id, nil)
      |> assign_batch(RecipeBatch.find_by_id(id))

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    if socket.assigns.recipe_batch_id != id do
      {:noreply,
       socket
       |> assign(:recipe_batch_id, id)
       |> assign_batch(RecipeBatch.find_by_id(id))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:new_reading, reading}, socket) do
    sensor_id = reading["sensor_id"]

    if Enum.any?(socket.assigns.active_sensors, &(&1.id == sensor_id)) do
      send_update(LiveIotMetricsWeb.SensorLiveChart,
        id: "sensor-chart-#{sensor_id}",
        new_reading: reading
      )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:nodes_attached, _batch_sensors}, socket) do
    socket =
      socket
      |> assign_batch(RecipeBatch.find_by_id(socket.assigns.recipe_batch_id))
      |> assign(:show_attach_node_modal, false)
      |> put_flash(:info, "Node attached to batch")

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_attach_node", _params, socket) do
    {:noreply,
     socket
     |> assign(:available_nodes, Nodes.find_available())
     |> assign(:show_attach_node_modal, true)}
  end

  @impl true
  def handle_event("close_attach_node", _params, socket) do
    {:noreply, assign(socket, :show_attach_node_modal, false)}
  end

  @impl true
  def handle_event("manage_node", %{"node-id" => node_id}, socket) do
    {:noreply, assign(socket, :managing_node_id, node_id)}
  end

  @impl true
  def handle_event("close_node_modal", _params, socket) do
    {:noreply, assign(socket, :managing_node_id, nil)}
  end

  @impl true
  def handle_event("detach_node", %{"node-id" => node_id}, socket) do
    BatchSensor.end_tracking_for_node(socket.assigns.batch.id, node_id)

    socket =
      socket
      |> assign_batch(RecipeBatch.find_by_id(socket.assigns.recipe_batch_id))
      |> put_flash(:info, "Node detached from batch")

    {:noreply, socket}
  end

  defp assign_batch(socket, batch) do
    socket
    |> assign(:batch, batch)
    |> assign(:active_sensors, active_sensors(batch))
    |> assign(:sensors_by_node, group_by_node(batch))
  end

  defp active_sensors(nil), do: []

  defp active_sensors(batch) do
    batch.batch_sensors
    |> Enum.filter(&(is_nil(&1.ended_at) and &1.sensor))
    |> Enum.map(& &1.sensor)
  end

  defp group_by_node(nil), do: []

  defp group_by_node(batch) do
    batch.batch_sensors
    |> Enum.filter(& &1.sensor)
    |> Enum.group_by(& &1.sensor.node)
    |> Enum.sort_by(fn {node, _} -> node && node.name end)
  end

  defp matching_range(nil, _sensor_type), do: nil

  defp matching_range(recipe, sensor_type) do
    Enum.find(recipe.property_ranges || [], &(&1.sensor_type == sensor_type))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LiveMetricsWeb.Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/"} class="btn btn-sm btn-ghost">
            <.icon name="hero-arrow-left" class="w-4 h-4 mr-2" /> Back
          </.link>
          <h1 class="text-3xl font-bold text-primary">Batch Details</h1>
        </div>

        <%= if is_nil(@batch) do %>
          <div class="alert alert-error shadow-lg mt-4">
            <div>
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="stroke-current flex-shrink-0 h-6 w-6"
                fill="none"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              <span>Batch not found.</span>
            </div>
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div class="card bg-base-200 shadow-xl border border-base-300">
              <div class="card-body">
                <h2 class="card-title text-primary">
                  <.icon name="hero-clipboard-document-list" class="w-6 h-6" />
                  {@batch.name}
                </h2>
                <div class="divider mt-0 mb-2"></div>

                <div class="space-y-3">
                  <div class="flex justify-between items-center">
                    <span class="text-base-content/70">Recipe</span>
                    <span class="font-semibold badge badge-secondary">{@batch.recipe.name}</span>
                  </div>

                  <div class="flex justify-between items-center">
                    <span class="text-base-content/70">Started</span>
                    <span class="font-mono text-sm">
                      {Calendar.strftime(@batch.started_at, "%Y-%m-%d %H:%M:%S")}
                    </span>
                  </div>

                  <div class="flex justify-between items-center">
                    <span class="text-base-content/70">Status</span>
                    <%= if @batch.ended_at do %>
                      <div class="badge badge-success">Completed</div>
                    <% else %>
                      <div class="badge badge-warning">Active</div>
                    <% end %>
                  </div>

                  <%= if @batch.ended_at do %>
                    <div class="flex justify-between items-center">
                      <span class="text-base-content/70">Ended</span>
                      <span class="font-mono text-sm">
                        {Calendar.strftime(@batch.ended_at, "%Y-%m-%d %H:%M:%S")}
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <div class="card bg-base-200 shadow-xl border border-base-300">
              <div class="card-body">
                <h2 class="card-title text-primary">
                  <.icon name="hero-information-circle" class="w-6 h-6" /> Recipe Description
                </h2>
                <div class="divider mt-0 mb-2"></div>
                <p class="text-base-content/80 whitespace-pre-wrap">{@batch.recipe.description}</p>
              </div>
            </div>
          </div>

          <div class="card bg-base-200 shadow-xl border border-base-300 mt-6">
            <div class="card-body">
              <div class="flex justify-between items-center">
                <h2 class="card-title text-primary">
                  <.icon name="hero-cpu-chip" class="w-6 h-6" /> Tracked Nodes
                </h2>
                <button phx-click="show_attach_node" class="btn btn-primary btn-sm">
                  <.icon name="hero-plus" class="w-4 h-4 mr-2" /> Attach Node
                </button>
              </div>
              <div class="divider mt-0 mb-4"></div>

              <%= if Enum.empty?(@sensors_by_node) do %>
                <div class="text-center py-8 text-base-content/60">
                  <p>No nodes are currently tracked for this batch.</p>
                </div>
              <% else %>
                <div class="space-y-6">
                  <%= for {node, batch_sensors} <- @sensors_by_node do %>
                    <div class="card bg-base-100 border border-base-300">
                      <div class="card-body">
                        <div class="flex justify-between items-center">
                          <h3 class="font-bold text-lg">
                            <.icon
                              name="hero-cpu-chip"
                              class="w-5 h-5 inline-block mr-1 text-secondary"
                            />
                            {if node, do: node.name, else: "Unknown node"}
                            <span :if={node} class="font-mono text-xs text-base-content/60">
                              {node.mac}
                            </span>
                          </h3>
                          <div :if={node} class="flex gap-2">
                            <button
                              phx-click="manage_node"
                              phx-value-node-id={node.id}
                              class="btn btn-ghost btn-outline btn-sm"
                            >
                              <.icon name="hero-cog-6-tooth" class="w-4 h-4 mr-1" /> Manage
                            </button>
                            <button
                              phx-click="detach_node"
                              phx-value-node-id={node.id}
                              data-confirm="Stop tracking every sensor of this node for the batch?"
                              class="btn btn-error btn-outline btn-sm"
                            >
                              <.icon name="hero-link-slash" class="w-4 h-4 mr-1" /> Detach Node
                            </button>
                          </div>
                        </div>

                        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4">
                          <%= for sensor_assoc <- batch_sensors do %>
                            <% range = matching_range(@batch.recipe, sensor_assoc.sensor.sensor_type) %>
                            <div class="bg-base-200 rounded-box p-4">
                              <div class="flex justify-between items-center mb-2">
                                <span class="font-medium capitalize">
                                  <.icon
                                    name="hero-signal"
                                    class="w-4 h-4 inline-block mr-1 text-accent"
                                  />
                                  {sensor_assoc.sensor.sensor_type}
                                </span>
                                <%= if sensor_assoc.ended_at do %>
                                  <span class="badge badge-sm">Ended</span>
                                <% else %>
                                  <span class="badge badge-success badge-sm badge-outline">
                                    Tracking
                                  </span>
                                <% end %>
                              </div>

                              <div class="flex flex-wrap gap-2 text-xs mb-2">
                                <span class="badge badge-outline">
                                  Batch range: {sensor_assoc.min_value} - {sensor_assoc.max_value}
                                </span>
                                <span :if={range} class="badge badge-info badge-outline">
                                  Recipe range: {range.min_value} - {range.max_value}
                                </span>
                              </div>

                              <.live_component
                                id={"sensor-chart-#{sensor_assoc.sensor.id}"}
                                module={LiveIotMetricsWeb.SensorLiveChart}
                                sensor_id={sensor_assoc.sensor.id}
                                interval={:last_hour}
                              />
                            </div>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <%= if @show_attach_node_modal do %>
            <.live_component
              id="attach-node-modal"
              module={AttachNodeModal}
              available_nodes={@available_nodes}
              property_ranges={@batch.recipe.property_ranges}
              recipe_batch_id={@batch.id}
            />
          <% end %>

          <%= if @managing_node_id do %>
            <.live_component id="node-modal" module={NodeModal} node_id={@managing_node_id} />
          <% end %>
        <% end %>
      </div>
    </LiveMetricsWeb.Layouts.app>
    """
  end
end
