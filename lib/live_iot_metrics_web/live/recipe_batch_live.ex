defmodule LiveMetricsWeb.RecipeBatchLive do
  alias LiveMetrics.Models.RecipeBatch
  use LiveMetricsWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _, socket) do
    batch = RecipeBatch.find_by_id(id)

    socket =
      socket
      |> assign(:recipe_batch_id, id)
      |> assign(:batch, batch)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    if socket.assigns.recipe_batch_id != id do
      batch = RecipeBatch.find_by_id(id)

      {:noreply,
       socket
       |> assign(:recipe_batch_id, id)
       |> assign(:batch, batch)}
    else
      {:noreply, socket}
    end
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
              <h2 class="card-title text-primary">
                <.icon name="hero-cpu-chip" class="w-6 h-6" /> Tracked Sensors
              </h2>
              <div class="divider mt-0 mb-4"></div>

              <%= if is_nil(@batch.batch_sensors) or Enum.empty?(@batch.batch_sensors) do %>
                <div class="text-center py-8 text-base-content/60">
                  <p>No sensors are currently tracked for this batch.</p>
                </div>
              <% else %>
                <div class="overflow-x-auto">
                  <table class="table table-zebra w-full">
                    <thead>
                      <tr>
                        <th>Sensor Type</th>
                        <th>Target Range</th>
                        <th>Tracking Started</th>
                        <th>Tracking Status</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for sensor_assoc <- @batch.batch_sensors do %>
                        <tr>
                          <td class="font-medium capitalize">
                            <.icon name="hero-signal" class="w-4 h-4 inline-block mr-1 text-accent" />
                            {if sensor_assoc.sensor,
                              do: sensor_assoc.sensor.sensor_type,
                              else: "Unknown"}
                          </td>
                          <td class="font-mono">
                            {sensor_assoc.min_value} - {sensor_assoc.max_value}
                          </td>
                          <td class="text-sm">
                            {Calendar.strftime(sensor_assoc.started_at, "%Y-%m-%d %H:%M")}
                          </td>
                          <td>
                            <%= if sensor_assoc.ended_at do %>
                              <span class="badge badge-sm">Ended</span>
                            <% else %>
                              <span class="badge badge-success badge-sm badge-outline">Tracking</span>
                            <% end %>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </LiveMetricsWeb.Layouts.app>
    """
  end
end
