defmodule LiveIotMetricsWeb.Dashboard.RecipeBatchCard do
  alias LiveMetrics.Models.RecipeBatch
  use LiveMetricsWeb, :html

  attr :recipe_batch, RecipeBatch, required: true, doc: "The recipe batch entry"

  @spec card(Plug.Conn.t()) :: Phoenix.LiveView.Rendered.t()
  def card(assigns) do
    batch = assigns.recipe_batch
    is_new = DateTime.diff(batch.started_at, DateTime.utc_now(), :day) <= 1
    date_format = "%Y-%m-%d"

    started_str = Calendar.strftime(batch.started_at, date_format)

    ended_str =
      if batch.ended_at,
        do: Calendar.strftime(batch.ended_at, date_format),
        else: nil

    assigns =
      assigns
      |> assign(:is_new, is_new)
      |> assign(:started_str, started_str)
      |> assign(:ended_str, ended_str)

    ~H"""
    <div class="card w-96 bg-base-100 card-md shadow-sm border border-base-200">
      <div class="card-body space-y-3">
        <h2 class="card-title text-primary">
          {@recipe_batch.name}
          <%= if @is_new do %>
            <span class="badge badge-secondary badge-sm">New</span>
          <% end %>
        </h2>

        <h3 class="text-secondary">{@recipe_batch.recipe.name}</h3>

        <div class="text-xs bg-base-200 p-3 rounded-box space-y-1 font-mono text-base-content/80">
          <div class="flex justify-between">
            <span class="font-bold text-base-content/60">Started:</span>
            <span>{@started_str}</span>
          </div>
          <div class="flex justify-between items-center">
            <%= if @ended_str do %>
              <span class="font-bold text-base-content/60">Ended:</span>
              <span>{@ended_str}</span>
            <% else %>
              <span class="badge badge-success badge-xs font-sans px-2 py-1 text-[10px] text-white">
                Active
              </span>
            <% end %>
          </div>
        </div>

        <div class="space-y-1">
          <span class="text-[11px] font-bold text-base-content/50 uppercase block">
            Active Sensors
          </span>
          <div class="grid grid-cols-3 gap-1">
            <%= for batch_sensor <- @recipe_batch.batch_sensors do %>
              <div class="badge badge-primary badge-outline text-[10px] w-full truncate justify-center">
                {batch_sensor.sensor.sensor_type}
              </div>
            <% end %>
          </div>
        </div>

        <div class="justify-end card-actions pt-2">
          <.link class="btn btn-primary btn-sm" navigate={~p"/recipe-batch/#{@recipe_batch.id}"}>
            Go to recipe
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
