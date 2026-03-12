defmodule LiveMetricsWeb.DashboardLive do
  use LiveMetricsWeb, :live_view

  alias LiveMetrics.Area
  alias LiveMetrics.Nodes
  alias LiveMetrics.Repo
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to metrics updates if you have pubsub
      Phoenix.PubSub.subscribe(LiveMetrics.PubSub, "metrics:update")
    end

    areas = Repo.all(Area)

    socket =
      socket
      |> assign(:areas, areas)
      |> assign(:active_area_id, List.first(areas) |> maybe_get_id())
      |> assign(:show_add_area_modal, false)
      |> assign(:show_add_node_modal, false)
      |> assign(:time_interval, :last_hour)
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

  def handle_event("save_area", %{"name" => name, "description" => desc}, socket) do
    case Area.create_area(%{name: name, description: desc}) do
      {:ok, area} ->
        areas = Repo.all(Area)

        socket =
          socket
          |> assign(:areas, areas)
          |> assign(:active_area_id, area.id)
          |> assign(:show_add_area_modal, false)
          |> put_flash(:info, "Area added successfully")
          |> load_active_area_nodes()

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Error creating area")}
    end
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

  def handle_event("save_nodes", %{"node_ids" => node_ids}, socket) do
    active_area_id = socket.assigns.active_area_id

    if active_area_id do
      # Update nodes to belong to this area
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

  # When form submits with no nodes selected
  def handle_event("save_nodes", _, socket) do
    {:noreply, assign(socket, :show_add_node_modal, false)}
  end

  def handle_event("set_interval", %{"interval" => interval}, socket) do
    socket =
      socket
      |> assign(:time_interval, String.to_existing_atom(interval))
      # In a real app, you would fetch new data here based on interval
      |> load_active_area_nodes()

    {:noreply, socket}
  end

  defp load_active_area_nodes(socket) do
    area_id = socket.assigns.active_area_id

    nodes =
      if area_id do
        Repo.all(
          from n in Nodes,
            where: n.area_id == ^area_id,
            preload: [:sensors]
        )
      else
        []
      end

    assign(socket, :active_nodes, nodes)
  end

  defp maybe_get_id(nil), do: nil
  defp maybe_get_id(struct), do: struct.id

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
    <div class="space-y-6">
      <div class="flex justify-between items-center">
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
        <div class="tabs tabs-boxed bg-base-200 p-2">
          <%= for area <- @areas do %>
            <a
              class={[
                "tab tab-lg",
                @active_area_id == area.id && "tab-active text-primary-content font-bold"
              ]}
              phx-click="select_area"
              phx-value-id={area.id}
            >
              {area.name}
            </a>
          <% end %>
        </div>

        <%= if @active_area_id do %>
          <div class="bg-base-200 rounded-box p-6 space-y-6">
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
                          <div class="stat-value text-lg">0</div>
                        </div>
                        <div class="stat px-4 py-2">
                          <div class="stat-title text-xs">Last Reading</div>
                          <div class="stat-value text-lg">-</div>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      <% end %>
      
    <!-- Add Area Modal -->
      <%= if @show_add_area_modal do %>
        <dialog class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-4">Add New Area</h3>
            <form phx-submit="save_area">
              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text">Name</span>
                </label>
                <input
                  type="text"
                  name="name"
                  class="input input-bordered w-full"
                  required
                  placeholder="E.g. Greenhouse 1"
                />
              </div>
              <div class="form-control mb-6">
                <label class="label">
                  <span class="label-text">Description</span>
                </label>
                <textarea
                  name="description"
                  class="textarea textarea-bordered h-24"
                  required
                  placeholder="Description of the area..."
                ></textarea>
              </div>
              <div class="modal-action">
                <button type="button" class="btn" phx-click="close_add_area">Cancel</button>
                <button type="submit" class="btn btn-primary">Save Area</button>
              </div>
            </form>
          </div>
          <form method="dialog" class="modal-backdrop" phx-click="close_add_area">
            <button>close</button>
          </form>
        </dialog>
      <% end %>
      
    <!-- Add Node Modal -->
      <%= if @show_add_node_modal do %>
        <dialog class="modal modal-open">
          <div class="modal-box max-w-2xl">
            <h3 class="font-bold text-lg mb-4">Assign Devices to Area</h3>

            <%= if Enum.empty?(@unassigned_nodes) do %>
              <div class="alert alert-info">
                <.icon name="hero-information-circle" class="w-6 h-6" />
                <span>
                  No available unassigned devices found. Device nodes will appear here when they connect and send data.
                </span>
              </div>
              <div class="modal-action">
                <button type="button" class="btn" phx-click="close_add_node">Close</button>
              </div>
            <% else %>
              <form phx-submit="save_nodes">
                <div class="overflow-x-auto max-h-96">
                  <table class="table table-zebra w-full">
                    <thead>
                      <tr>
                        <th>Select</th>
                        <th>Name</th>
                        <th>MAC Address</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for node <- @unassigned_nodes do %>
                        <tr>
                          <td>
                            <input
                              type="checkbox"
                              name="node_ids[]"
                              value={node.id}
                              class="checkbox checkbox-primary"
                            />
                          </td>
                          <td class="font-medium">{node.name}</td>
                          <td class="font-mono text-sm">{format_mac(node.mac)}</td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
                <div class="modal-action mt-6">
                  <button type="button" class="btn" phx-click="close_add_node">Cancel</button>
                  <button type="submit" class="btn btn-primary">Assign Selected</button>
                </div>
              </form>
            <% end %>
          </div>
          <form method="dialog" class="modal-backdrop" phx-click="close_add_node">
            <button>close</button>
          </form>
        </dialog>
      <% end %>
    </div>
    """
  end
end
