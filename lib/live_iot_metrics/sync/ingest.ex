defmodule LiveMetrics.Sync.Ingest do
  @moduledoc """
  Stores measurements extracted from a node (USB today; CoAP and LoRa later) and computes the
  confirmation sent back to it (docs/tundra/PLAN.md, section 5).

  Rules:

    * Only the measurement right after the watermark (`acked_seq + 1`) is accepted, in order.
      Anything at or below the watermark was already stored (a resend, or the same storage
      extracted twice) and is ignored. A measurement after a gap is ignored too: the node
      resends from `acked_seq + 1`, so nothing is stored twice and the table of readings needs
      no unique index (TimescaleDB would require the time column in it).
    * The watermark and the readings are written in the same transaction, with the node's row
      locked, so two extractions of the same node can not interleave.
    * Measurements taken without a valid clock (`ts = 0`) are counted and skipped: their time
      is unknown. They still advance the watermark so the node can release them.
  """
  import Ecto.Query

  alias LiveMetrics.Models.{NodeSensorConfig, Nodes, Sensor}
  alias LiveMetrics.Repo
  alias LiveMetrics.Sync.{MeasurementCbor, NodeSyncState}

  @type sensor_meta :: %{optional(non_neg_integer()) => %{type: String.t(), precision: float()}}

  @doc "Watermark of a node (0 if it never synchronized)."
  @spec acked_seq(String.t()) :: non_neg_integer()
  def acked_seq(mac) do
    case Repo.get_by(NodeSyncState, mac: normalize_mac(mac)) do
      nil -> 0
      state -> state.acked_seq
    end
  end

  @doc """
  Ingests concatenated CBOR records of `mac`.

  `sensors` describes the node's sensors as reported by the node itself
  (`id => %{type, precision}`); records of sensors no longer configured on the node are typed
  from the server records instead (see `sensor_types/2`).

  Returns the new watermark plus how many records were stored, ignored and skipped.
  """
  @spec ingest(String.t(), binary(), sensor_meta()) ::
          {:ok,
           %{
             acked_seq: non_neg_integer(),
             stored: non_neg_integer(),
             ignored: non_neg_integer(),
             skipped_without_time: non_neg_integer()
           }}
          | {:error, term()}
  def ingest(mac, records_binary, sensors \\ %{}) do
    mac = normalize_mac(mac)

    with {:ok, measurements} <- MeasurementCbor.decode_all(records_binary) do
      Repo.transaction(fn ->
        state = lock_state(mac)
        {accepted, acked_seq} = take_contiguous(measurements, state.acked_seq)
        {with_time, without_time} = Enum.split_with(accepted, &(&1.ts > 0))

        types = sensor_types(mac, sensors)

        if with_time != [] do
          entries = Enum.map(with_time, &to_entry(&1, mac, types))
          Repo.query!("SELECT insert_reading_in_batch($1)", [entries])
        end

        state
        |> Ecto.Changeset.change(
          acked_seq: acked_seq,
          received_count: state.received_count + length(with_time),
          skipped_without_time: state.skipped_without_time + length(without_time),
          last_sync_at: DateTime.utc_now()
        )
        |> Repo.update!()

        %{
          acked_seq: acked_seq,
          stored: length(with_time),
          ignored: length(measurements) - length(accepted),
          skipped_without_time: length(without_time)
        }
      end)
    end
  end

  # Keeps the run of measurements that continues the watermark without gaps
  defp take_contiguous(measurements, acked_seq) do
    Enum.reduce(measurements, {[], acked_seq}, fn m, {acc, watermark} ->
      if m.seq == watermark + 1, do: {[m | acc], m.seq}, else: {acc, watermark}
    end)
    |> then(fn {acc, watermark} -> {Enum.reverse(acc), watermark} end)
  end

  defp lock_state(mac) do
    Repo.insert!(%NodeSyncState{mac: mac}, on_conflict: :nothing, conflict_target: :mac)

    NodeSyncState
    |> where([s], s.mac == ^mac)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  # Sensor types and precision by node sensor id: what the node reports first, then the
  # configuration saved from the setup screen, then the sensors the server already knows.
  defp sensor_types(mac, reported) do
    configured =
      mac
      |> NodeSensorConfig.list_by_mac()
      |> Map.new(&{&1.id, %{type: &1.sensor_type, precision: &1.precision}})

    known =
      from(s in Sensor,
        join: n in Nodes,
        on: n.id == s.node_id,
        where: n.mac == ^mac,
        select: {s.node_sensor_id, %{type: s.sensor_type, precision: s.precision}}
      )
      |> Repo.all()
      |> Map.new()

    known |> Map.merge(configured) |> Map.merge(reported)
  end

  defp to_entry(m, mac, types) do
    meta = Map.get(types, m.sensor_id, %{type: "sensor_#{m.sensor_id}", precision: 1.0})

    %{
      mac: mac,
      sensor_id: m.sensor_id,
      sensor_type: String.downcase(meta.type),
      precision: meta.precision,
      value: m.value,
      reading_time: m.ts |> DateTime.from_unix!() |> DateTime.to_iso8601()
    }
  end

  defp normalize_mac(mac), do: mac |> String.trim() |> String.upcase()
end
