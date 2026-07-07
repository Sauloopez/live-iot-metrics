defmodule LiveMetricsWeb.DashboardLive do
  use LiveMetricsWeb, :live_view

  alias LiveMetrics.Models.Area
  alias LiveMetrics.Models.Nodes
  alias LiveMetrics.Repo
  alias LiveMetricsWeb.Components.AddNodeModal
  alias LiveMetricsWeb.Components.AddAreaModal
  alias LiveMetricsWeb.Components.AreasTabs

  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      IO.puts("connected to socket")
      Phoenix.PubSub.subscribe(LiveMetrics.PubSub, "sensor_readings")
    end

    areas = Repo.all(Area)

    socket =
      socket
      |> assign(:areas, areas)
      |> assign(:active_area_id, List.first(areas) |> maybe_get_id())
      |> assign(:show_add_area_modal, false)
      |> assign(:show_add_node_modal, false)
      |> assign(:time_interval, :last_hour)
      |> assign(:latest_readings, %{})
      |> assign(:unassigned_nodes, [])
      |> load_active_area_nodes()

    {:ok, socket}
  end

  @impl true
  def handle_event("select_area", %{"id" => id}, socket) do
    socket =
      socket
      |> assign(:active_area_id, id)
      |> load_active_area_nodes()

    {:noreply, socket}
  end

  def handle_event("show_add_area", _, socket) do
    {:noreply, assign(socket, :show_add_area_modal, true)}
  end

  def handle_event("close_add_area", _, socket) do
    {:noreply, assign(socket, :show_add_area_modal, false)}
  end

  def handle_event("show_add_node", _, socket) do
    unassigned_nodes = Repo.all(from n in Nodes, where: is_nil(n.area_id))

    {:noreply,
     socket
     |> assign(:show_add_node_modal, true)
     |> assign(:unassigned_nodes, unassigned_nodes)}
  end

  def handle_event("close_add_node", _, socket) do
    {:noreply, assign(socket, :show_add_node_modal, false)}
  end

  def handle_event("set_interval", %{"interval" => interval}, socket) do
    socket =
      socket
      |> assign(:time_interval, String.to_existing_atom(interval))
      |> load_active_area_nodes()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:area_created, area}, socket) do
    areas = Repo.all(Area)

    socket =
      socket
      |> assign(:areas, areas)
      |> assign(:active_area_id, area.id)
      |> assign(:show_add_area_modal, false)
      |> put_flash(:info, "Area added successfully")
      |> load_active_area_nodes()

    {:noreply, socket}
  end

  def handle_info({:area_creation_failed, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_info({:assign_nodes, node_ids}, socket) do
    active_area_id = socket.assigns.active_area_id

    if active_area_id do
      {count, _} =
        Repo.update_all(
          from(n in Nodes, where: n.id in ^node_ids),
          set: [area_id: active_area_id]
        )

      socket =
        socket
        |> assign(:show_add_node_modal, false)
        |> put_flash(:info, "Added #{count} devices to the area")
        |> load_active_area_nodes()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:close_node_modal}, socket) do
    {:noreply, assign(socket, :show_add_node_modal, false)}
  end

  def handle_info({:new_reading, reading}, socket) do
    node_id = reading.sensor.node_id

    socket =
      if Enum.any?(socket.assigns.active_nodes, &(&1.id == node_id)) do
        new_readings =
          Map.put(socket.assigns.latest_readings || %{}, node_id, %{
            value: reading.value,
            time: reading.reading_time
          })

        send_update(LiveIotMetricsWeb.SensorLiveChart,
          id: "sensor-chart-#{reading.sensor_id}",
          new_reading: reading
        )

        assign(socket, :latest_readings, new_readings)
      else
        socket
      end

    {:noreply, socket}
  end

  # --- Privates de Carga de Datos y Formateo ---

  defp load_active_area_nodes(socket) do
    area_id = socket.assigns.active_area_id

    nodes =
      if area_id do
        Repo.all(from n in Nodes, where: n.area_id == ^area_id, preload: [:sensors])
      else
        []
      end

    assign(socket, :active_nodes, nodes)
  end

  defp maybe_get_id(nil), do: nil
  defp maybe_get_id(struct), do: struct.id

  defp format_mac(nil), do: ""

  defp format_mac(mac) when is_binary(mac) do
    mac |> Base.encode16() |> to_charlist() |> Enum.chunk_every(2) |> Enum.join(":")
  end

  defp areas_tabs(assigns) do
    AreasTabs.render(assigns)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LiveMetricsWeb.Layouts.app flash={@flash}>
      <div class="">
        <div class="flex justify-between items-center mb-10">
          <h1 class="text-3xl font-bold text-primary">Dashboard</h1>
          <button phx-click="show_add_area" class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="w-4 h-4 mr-2" /> Add Area
          </button>
        </div>

        <%= if Enum.empty?(@areas) do %>
          <div class="hero bg-base-200 rounded-box py-12">
            <div class="hero-content text-center">
              <div class="max-w-md">
                <h1 class="text-2xl font-bold">No Areas Yet</h1>
                <p class="py-6">Get started by creating your first tracking area.</p>
                <button phx-click="show_add_area" class="btn btn-primary">Create Area</button>
              </div>
            </div>
          </div>
        <% else %>
          <.areas_tabs areas={@areas} active_area_id={@active_area_id} />

          <%= if @active_area_id do %>
            <div class="bg-base-200 rounded-box p-6 space-y-6 mt-4">
              <div class="flex justify-between items-center flex-wrap gap-4">
                <h2 class="text-xl font-bold">Area Devices</h2>

                <div class="flex items-center gap-4">
                  <div class="join">
                    <button
                      class={["btn btn-sm join-item", @time_interval == :last_minute && "btn-active"]}
                      phx-click="set_interval"
                      phx-value-interval="last_minute"
                    >
                      Last minute
                    </button>
                    <button
                      class={["btn btn-sm join-item", @time_interval == :last_hour && "btn-active"]}
                      phx-click="set_interval"
                      phx-value-interval="last_hour"
                    >
                      Last hour
                    </button>
                    <button
                      class={["btn btn-sm join-item", @time_interval == :last_day && "btn-active"]}
                      phx-click="set_interval"
                      phx-value-interval="last_day"
                    >
                      Last day
                    </button>
                  </div>

                  <button phx-click="show_add_node" class="btn btn-secondary btn-sm">
                    <.icon name="hero-plus" class="w-4 h-4 mr-2" /> Add Device
                  </button>
                </div>
              </div>

              <%= if Enum.empty?(@active_nodes) do %>
                <div class="text-center py-12 text-base-content/70">
                  <.icon name="hero-cpu-chip" class="w-12 h-12 mx-auto mb-4 opacity-50" />
                  <p>No devices assigned to this area.</p>
                </div>
              <% else %>
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                  <%= for node <- @active_nodes do %>
                    <div class="card bg-base-100 shadow-xl border border-base-300">
                      <div class="card-body">
                        <h2 class="card-title text-primary">
                          <.icon name="hero-cpu-chip" class="w-5 h-5" />
                          {node.name}
                        </h2>
                        <div class="text-xs text-base-content/70 mb-4 font-mono">
                          {format_mac(node.mac)}
                        </div>

                        <div class="stats stats-vertical bg-base-200 shadow">
                          <div class="stat px-4 py-2">
                            <div class="stat-title text-xs">Sensors</div>
                            <div class="stat-value text-lg">{length(node.sensors)}</div>
                          </div>
                          <%= for sensor <- node.sensors do %>
                            <div class="stat px-4 py-2">
                              <div class="stat-title text-xs">{sensor.sensor_type}</div>
                              <.live_component
                                id={"sensor-chart-#{sensor.id}"}
                                module={LiveIotMetricsWeb.SensorLiveChart}
                                sensor_id={sensor.id}
                                interval={@time_interval}
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
          <% end %>
        <% end %>
        <%= if @show_add_area_modal do %>
          <.live_component id="add-area-modal" module={AddAreaModal} />
        <% end %>

        <%= if @show_add_node_modal do %>
          <.live_component
            id="add-node-modal"
            module={AddNodeModal}
            unassigned_nodes={@unassigned_nodes}
            format_mac_fun={&format_mac/1}
          />
        <% end %>
      </div>
    </LiveMetricsWeb.Layouts.app>
    """
  end
end
