defmodule LiveMetrics.SensorReadingListener do
  use GenServer
  require Logger
  alias Postgrex.Notifications

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    db_config = LiveMetrics.Repo.config()
    {:ok, pid} = Notifications.start_link(db_config)
    {:ok, ref} = Notifications.listen(pid, "sensor_reading")
    {:ok, %{pid: pid, ref: ref}}
  end

  @impl true

  def handle_info({:notification, _connection_pid, _ref, "sensor_reading", payload}, state) do
    case Jason.decode(payload) do
      {:ok, data} ->
        handle_new_reading(data)

      {:error, error} ->
        Logger.error("Error during JSON decoding: #{inspect(error)}")
    end

    {:noreply, state}
  end

  defp handle_new_reading(reading) do
    Phoenix.PubSub.broadcast(
      LiveMetrics.PubSub,
      "sensor_readings",
      {:new_reading, reading}
    )
  end
end
