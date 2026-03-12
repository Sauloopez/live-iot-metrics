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
    </LiveMetricsWeb.Layouts.app>
    """
  end
end
