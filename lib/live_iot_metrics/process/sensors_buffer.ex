defmodule LiveMetrics.SensorsBuffer do
  @moduledoc """
  Queue of `POST /sensors` lists (`LiveMetrics.Sync.CoapResources.sensors/1`): registers the
  node and its sensors so the measurements it syncs get the right type.

  If a sensor list and the first measurements of a node arrive together, the measurements may
  be stored before the list; their sensor gets its real type as soon as the list is processed.
  """
  use LiveMetrics.QueueBuffer, flush_interval_ms: 1000, max_batch: 20

  alias LiveMetrics.Models.{Nodes, Sensor}

  @doc "Queues the `sensor list` items (`i`, `t`, `pr`) of `mac`."
  def push(mac, sensors), do: enqueue({mac, sensors})

  @impl LiveMetrics.QueueBuffer
  def process_batch(lists) do
    # Only the newest list of each node matters
    lists
    |> Enum.reverse()
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.each(fn {mac, sensors} -> register(mac, sensors) end)
  end

  defp register(mac, sensors) do
    {:ok, node} = Nodes.ensure(mac)

    for %{"i" => id, "t" => type} = s <- sensors, is_integer(id) and is_binary(type) do
      Sensor.update_or_create(node, id, String.downcase(type), (s["pr"] || 1) * 1.0)
    end
  end
end
