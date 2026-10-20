defmodule LiveIotMetricsWeb.SensorLiveChart do
  @moduledoc """
  LiveComponent to show sensor metrics in real time.

  uses :sensor_id and :interval to fetch historical data and subscribe to real-time updates.
  :interval values are :last_hour, :last_day or :last_minute

  Optional :range_min and :range_max shade the target range on the chart and flag
  readings outside of it. :label names the series for tooltips and screen readers.
  When :ended_at is set the chart shows the interval up to that moment and is not live.

  """
  use LiveMetricsWeb, :live_component
  alias LiveMetrics.Repo
  import Ecto.Query

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket, data_points: [], range_min: nil, range_max: nil, label: nil, ended_at: nil)}
  end

  @impl true
  def update(%{sensor_id: sensor_id, interval: interval} = assigns, socket) do
    now = assigns[:ended_at] || DateTime.utc_now(:second)

    start_time =
      case interval do
        :last_hour -> DateTime.add(now, -3600, :second)
        :last_day -> DateTime.add(now, -86400, :second)
        :last_minute -> DateTime.add(now, -60, :second)
        _ -> 60
      end

    historical_data =
      LiveMetrics.Models.SensorReading
      |> where([r], r.sensor_id == ^sensor_id)
      |> where([r], r.reading_time >= ^start_time and r.reading_time <= ^now)
      |> order_by(desc: :reading_time)
      |> limit(50)
      |> Repo.all()
      |> Enum.map(fn r ->
        %{
          value: r.value,
          time: DateTime.to_iso8601(r.reading_time)
        }
      end)
      |> Enum.reverse()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:historical_data, historical_data)}
  end

  @impl true
  def update(%{new_reading: reading}, socket) do
    current_data = socket.assigns.historical_data

    new_point = %{
      value: reading["value"],
      time: reading["reading_time"],
      sensor_id: reading["sensor_id"]
    }

    # Readings can arrive out of order (batches are inserted concurrently)
    updated_data =
      (current_data ++ [new_point])
      |> Enum.sort_by(&reading_time_key/1)
      |> Enum.take(-50)

    {:ok,
     socket
     |> assign(:historical_data, updated_data)
     |> push_event("new-data", Map.put(new_point, :chart_id, socket.assigns.id))}
  end

  attr :sensor_id, :integer
  attr :interval, :atom
  attr :historical_data, :list, default: []
  attr :range_min, :float, default: nil
  attr :range_max, :float, default: nil
  attr :label, :string, default: nil
  attr :ended_at, :any, default: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"chart-wrapper-#{@id}"} class="chart-wrapper viz-root w-full">
      <div class="flex items-center justify-between mb-2">
        <div :if={is_nil(@ended_at)} class="flex items-center gap-2">
          <span class="relative flex h-2 w-2">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-75">
            </span>
            <span class="relative inline-flex rounded-full h-2 w-2 bg-success"></span>
          </span>
          <span class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
            Live
          </span>
        </div>
        <div :if={@ended_at} class="flex items-center gap-2 text-base-content/50">
          <.icon name="hero-stop-circle-mini" class="w-4 h-4" />
          <span class="text-xs font-semibold uppercase tracking-wide">
            Stopped {Calendar.strftime(@ended_at, "%H:%M:%S")}
          </span>
        </div>

        <%= if last = List.last(@historical_data) do %>
          <div class="flex items-center gap-3">
            <%= case range_status(last.value, @range_min, @range_max) do %>
              <% :in_range -> %>
                <span
                  id={"chart-status-#{@id}"}
                  class="badge badge-sm badge-success badge-soft gap-1"
                >
                  <.icon name="hero-check-circle-mini" class="w-3.5 h-3.5" /> In range
                </span>
              <% :out_of_range -> %>
                <span id={"chart-status-#{@id}"} class="badge badge-sm badge-error badge-soft gap-1">
                  <.icon name="hero-exclamation-triangle-mini" class="w-3.5 h-3.5" /> Out of range
                </span>
              <% :unknown -> %>
            <% end %>
            <div class="text-right leading-tight">
              <span class="font-mono font-bold text-lg tabular-nums">{format_value(last.value)}</span>
              <span class="block text-[10px] text-base-content/50">{format_time(last.time)}</span>
            </div>
          </div>
        <% else %>
          <span class="badge badge-ghost badge-sm">No data</span>
        <% end %>
      </div>

      <div class="relative bg-base-100 border border-base-300 rounded-box p-3 transition-shadow hover:shadow-sm">
        <div
          id={"chart-canvas-#{@id}"}
          phx-hook="ChartHook"
          phx-update="ignore"
          data-sensor-id={@sensor_id}
          data-chart-id={@id}
          data-label={@label}
          data-min={@range_min}
          data-max={@range_max}
          data-readings={Jason.encode!(@historical_data)}
          class="relative w-full h-64"
        >
        </div>
        <div
          :if={Enum.empty?(@historical_data)}
          class="absolute inset-0 flex items-center justify-center text-sm text-base-content/40 pointer-events-none"
        >
          Waiting for readings...
        </div>
      </div>

      <details
        :if={@historical_data != []}
        id={"chart-table-#{@id}"}
        class="group mt-2"
        phx-mounted={JS.ignore_attributes(["open"])}
      >
        <summary class="cursor-pointer select-none text-xs text-base-content/60 hover:text-base-content transition-colors">
          View data
        </summary>
        <div class="mt-2 max-h-48 overflow-y-auto rounded-box border border-base-300">
          <table class="table table-xs">
            <thead>
              <tr>
                <th>Time</th>
                <th class="text-right">Value</th>
                <th :if={@range_min && @range_max}>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={reading <- Enum.reverse(@historical_data)}>
                <td class="font-mono">{format_time(reading.time)}</td>
                <td class="font-mono text-right tabular-nums">{format_value(reading.value)}</td>
                <td :if={@range_min && @range_max}>
                  <%= if range_status(reading.value, @range_min, @range_max) == :out_of_range do %>
                    <span class="text-error">
                      <.icon name="hero-exclamation-triangle-mini" class="w-3.5 h-3.5" /> Out
                    </span>
                  <% else %>
                    <span class="text-base-content/60">In</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>
    </div>
    """
  end

  defp reading_time_key(%{time: time}) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _offset} -> DateTime.to_unix(dt, :microsecond)
      _error -> 0
    end
  end

  defp reading_time_key(_reading), do: 0

  defp range_status(value, min, max)
       when is_number(value) and is_number(min) and is_number(max) do
    if value < min or value > max, do: :out_of_range, else: :in_range
  end

  defp range_status(_value, _min, _max), do: :unknown

  defp format_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp format_value(value), do: to_string(value)

  defp format_time(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> Calendar.strftime(dt, "%H:%M:%S")
      _error -> iso
    end
  end

  defp format_time(_iso), do: ""
end
