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
      LiveMetrics.SensorReading
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
    IO.puts("SensorLiveChart received new reading")
    current_data = socket.assigns.historical_data

    new_point = %{
      value: reading.value,
      time: DateTime.to_iso8601(reading.reading_time),
      sensor_id: reading.sensor_id
    }

    updated_data =
      (current_data ++ [new_point])
      |> Enum.take(-50)

    {:ok,
     socket
     |> assign(:historical_data, updated_data)
     |> push_event("new-data", new_point)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"chart-wrapper-#{@id}"} class="chart-wrapper">
      <div
        id={"chart-canvas-#{@id}"}
        phx-hook="ChartHook"
        phx-update="ignore"
        data-sensor-id={@sensor_id}
        data-readings={Jason.encode!(@historical_data)}
      >
      </div>
    </div>
    """
  end
end
