defmodule LiveMetricsWeb.DevicesLive do
  use LiveMetricsWeb, :live_view

  alias LiveMetrics.Models.Nodes
  alias LiveMetricsWeb.Components.NodeModal

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:managing_node_id, nil)
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
          <.link id="device-setup-link" navigate={~p"/devices/setup"} class="btn btn-secondary btn-sm">
            <.icon name="hero-bolt" class="w-4 h-4 mr-2" /> Configure via USB
          </.link>
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
                  id={"manage-node-#{node.id}"}
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
    </LiveMetricsWeb.Layouts.app>
    """
  end
end
