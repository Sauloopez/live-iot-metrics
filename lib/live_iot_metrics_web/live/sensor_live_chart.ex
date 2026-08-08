defmodule LiveIotMetricsWeb.SensorLiveChart do
  @moduledoc """
  LiveComponent to show sensor metrics in real time.

  uses :sensor_id and :interval to fetch historical data and subscribe to real-time updates.
  :interval values are :last_hour, :last_day or :last_minute

  """
  use LiveMetricsWeb, :live_component
  alias LiveMetrics.Repo
  import Ecto.Query

  @impl true
  def mount(socket) do
    {:ok, assign(socket, data_points: [])}
  end

  @impl true
  def update(%{sensor_id: sensor_id, interval: interval} = assigns, socket) do
    now = DateTime.utc_now(:second)

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

    updated_data =
      (current_data ++ [new_point])
      |> Enum.take(-50)

    {:ok,
     socket
     |> assign(:historical_data, updated_data)
     |> push_event("new-data", new_point)}
  end

  attr :sensor_id, :integer
  attr :interval, :atom
  attr :historical_data, :list, default: []

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"chart-wrapper-#{@id}"} class="chart-wrapper w-full">
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-2">
          <span class="relative flex h-2 w-2">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-75">
            </span>
            <span class="relative inline-flex rounded-full h-2 w-2 bg-success"></span>
          </span>
          <span class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
            Live
          </span>
        </div>

        <%= if last = List.last(@historical_data) do %>
          <div class="text-right leading-tight">
            <span class="font-mono font-bold text-lg">{last.value}</span>
            <span class="block text-[10px] text-base-content/50">{format_time(last.time)}</span>
          </div>
        <% else %>
          <span class="badge badge-ghost badge-sm">No data</span>
        <% end %>
      </div>

      <div class="relative bg-base-100 border border-base-300 rounded-box p-2">
        <div
          id={"chart-canvas-#{@id}"}
          phx-hook="ChartHook"
          phx-update="ignore"
          data-sensor-id={@sensor_id}
          data-readings={Jason.encode!(@historical_data)}
          class="w-full"
        >
        </div>
        <div
          :if={Enum.empty?(@historical_data)}
          class="absolute inset-0 flex items-center justify-center text-sm text-base-content/40 pointer-events-none"
        >
          Waiting for readings...
        </div>
      </div>
    </div>
    """
  end

  defp format_time(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> Calendar.strftime(dt, "%H:%M:%S")
      _error -> iso
    end
  end

  defp format_time(_iso), do: ""
end
