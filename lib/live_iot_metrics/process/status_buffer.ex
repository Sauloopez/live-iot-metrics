defmodule LiveMetrics.StatusBuffer do
  @moduledoc """
  Queue of `POST /status` health reports (`LiveMetrics.Sync.CoapResources.status/1`), stored
  in batches as `LiveMetrics.Health.NodeStatusReport`s with transport `coap`.
  """
  use LiveMetrics.QueueBuffer, flush_interval_ms: 1000, max_batch: 20

  alias LiveMetrics.Health.NodeStatusReport

  @doc "Queues a decoded `status` document (short keys) of `mac`."
  def push(mac, status), do: enqueue({mac, status})

  @impl LiveMetrics.QueueBuffer
  def process_batch(reports) do
    Enum.each(reports, fn {mac, status} ->
      case NodeStatusReport.record(mac, status["v"], "coap", status) do
        {:ok, _report} -> :ok
        {:error, reason} -> Logger.warning("Status of #{mac} rejected: #{inspect(reason)}")
      end
    end)
  end
end
