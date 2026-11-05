defmodule LiveMetrics.SyncBuffer do
  @moduledoc """
  Queue of `POST /sync` frames (`LiveMetrics.Sync.CoapResources.sync/1`).

  The CoAP answer carries the node's **last processed watermark**, read from an ETS cache;
  the confirmation of the frame just received arrives in a later exchange. That is safe: the
  node only releases what the server confirmed, and the watermark ignores resends.

  Each batch groups the frames by node and stores them in `seq` order with
  `LiveMetrics.Sync.Ingest`, then refreshes the cached watermark.
  """
  use LiveMetrics.QueueBuffer, flush_interval_ms: 500, max_batch: 50

  alias LiveMetrics.Sync.Ingest

  @table :sync_watermarks

  @impl LiveMetrics.QueueBuffer
  def setup, do: :ets.new(@table, [:named_table, :public, read_concurrency: true])

  @doc "Queues the CBOR records of a DATA frame of `mac`."
  def push(mac, first_seq, records), do: enqueue({mac, first_seq, records})

  @doc "Last processed watermark of `mac` (from ETS; the database only the first time)."
  def watermark(mac) do
    case :ets.lookup(@table, mac) do
      [{^mac, acked}] ->
        acked

      [] ->
        acked = Ingest.acked_seq(mac)
        :ets.insert_new(@table, {mac, acked})
        acked
    end
  end

  @doc "Forgets cached watermarks (tests: the sandbox rolls the database back)."
  def clear_cache, do: :ets.delete_all_objects(@table)

  @impl LiveMetrics.QueueBuffer
  def process_batch(frames) do
    frames
    |> Enum.group_by(fn {mac, _, _} -> mac end, fn {_, first, records} -> {first, records} end)
    |> Enum.each(fn {mac, node_frames} -> ingest(mac, node_frames) end)
  end

  defp ingest(mac, frames) do
    records =
      frames
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.map_join(&elem(&1, 1))

    case Ingest.ingest(mac, records) do
      {:ok, %{acked_seq: acked}} -> :ets.insert(@table, {mac, acked})
      {:error, reason} -> Logger.warning("Sync of #{mac} rejected: #{inspect(reason)}")
    end
  end
end
