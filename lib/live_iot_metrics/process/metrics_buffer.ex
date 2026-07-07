defmodule LiveMetrics.MetricsBuffer do
  use GenServer
  require Logger

  @flush_interval_ms 1000
  @batch_size 10

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def enqueue(
        mac,
        sensor_id,
        sensor_type,
        precision,
        value,
        reading_time
      ) do
    GenServer.cast(
      __MODULE__,
      {:enqueue,
       %{
         mac: mac,
         sensor_id: sensor_id,
         sensor_type: sensor_type,
         precision: precision,
         value: value,
         reading_time: reading_time
       }}
    )
  end

  @impl true
  def init(_) do
    schedule_flush()
    {:ok, %{buffer: [], count: 0}}
  end

  @impl true
  def handle_cast({:enqueue, metric}, %{buffer: buf, count: n} = state) do
    new_state = %{state | buffer: [metric | buf], count: n + 1}

    if new_state.count >= @batch_size do
      flush(new_state)
    else
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    schedule_flush()
    flush(state)
  end

  defp flush(%{buffer: []} = state), do: {:noreply, state}

  defp flush(%{buffer: buf}) do
    Task.start(fn -> process_batch(Enum.reverse(buf)) end)
    {:noreply, %{buffer: [], count: 0}}
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end

  defp process_batch(metrics) do
    LiveMetrics.Metrics.Processor.process_batch(metrics)
  rescue
    e ->
      Logger.error("Batch processing failed: #{inspect(e)}")
  end
end
