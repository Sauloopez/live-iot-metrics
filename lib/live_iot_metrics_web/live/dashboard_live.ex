defmodule LiveMetricsWeb.DashboardLive do
  alias LiveIotMetricsWeb.Dashboard.AreaRecipes
  use LiveMetricsWeb, :live_view

  alias LiveMetrics.Models.Area
  alias LiveMetricsWeb.Components.AddAreaModal
  alias LiveMetricsWeb.Components.AreasTabs

  @impl true
  def mount(_params, _session, socket) do
    areas = Area.find_all_sorted_by_name()

    active_area_id = List.first(areas) |> maybe_get_id()

    active_area =
      case active_area_id do
        nil ->
          nil

        id ->
          Area.find_area_with_recipes(id)
      end

    socket =
      socket
      |> assign(:areas, areas)
      |> assign(:active_area, active_area)
      |> assign(:active_area_id, active_area_id)
      |> assign(:show_add_area_modal, false)
      |> assign(:show_add_node_modal, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_area", %{"id" => id}, socket) do
    socket =
      socket
      |> assign(:active_area, Area.find_area_with_recipes(id))
      |> assign(:active_area_id, id)

    {:noreply, socket}
  end

  def handle_event("show_add_area", _, socket) do
    {:noreply, assign(socket, :show_add_area_modal, true)}
  end

  def handle_event("close_add_area", _, socket) do
    {:noreply, assign(socket, :show_add_area_modal, false)}
  end

  @impl true
  def handle_info({:area_created, area}, socket) do
    new_areas = Enum.sort_by([area | socket.assigns.areas], & &1.name)

    socket =
      socket
      |> assign(:areas, new_areas)
      |> assign(:active_area_id, area.id)
      |> assign(:active_area, Area.find_area_with_recipes(area.id))
      |> assign(:show_add_area_modal, false)
      |> put_flash(:info, "Area added successfully")

    {:noreply, socket}
  end

  def handle_info({:area_creation_failed, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  defp maybe_get_id(nil), do: nil
  defp maybe_get_id(struct), do: struct.id

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
          <AreasTabs.tabs areas={@areas} active_area_id={@active_area_id} />
          <%= if @active_area_id do %>
            <div class="bg-base-200 rounded-box p-6 space-y-6 mt-4">
              <div class="flex justify-between items-center flex-wrap gap-4">
                <h2 class="text-xl font-bold">Area Recipes</h2>
              </div>
              <AreaRecipes.grid area_recipes={@active_area.batches} />
            </div>
          <% end %>
        <% end %>
        <%= if @show_add_area_modal do %>
          <.live_component id="add-area-modal" module={AddAreaModal} />
        <% end %>
      </div>
    </LiveMetricsWeb.Layouts.app>
    """
  end
end
