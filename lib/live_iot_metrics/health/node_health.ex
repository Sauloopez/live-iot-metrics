defmodule LiveMetrics.Health.NodeHealth do
  @moduledoc """
  Health summary of each node for the Devices screen: what the node last reported, when it was
  last seen (a measurement or a report, whichever is newer), its last synchronization and the
  alerts derived from them.
  """
  import Ecto.Query

  alias LiveMetrics.Health.NodeStatusReport
  alias LiveMetrics.Models.{Sensor, SensorReading}
  alias LiveMetrics.Repo
  alias LiveMetrics.Sync.NodeSyncState

  @low_battery_percent 20
  @storage_full_ratio 0.9
  @sync_overdue_days 7

  def thresholds,
    do: %{
      low_battery_percent: @low_battery_percent,
      storage_full_ratio: @storage_full_ratio,
      sync_overdue_days: @sync_overdue_days
    }

  @doc "Summaries for the given nodes, keyed by node id."
  def summaries(nodes, now \\ DateTime.utc_now()) do
    macs = Enum.map(nodes, & &1.mac)
    reports = NodeStatusReport.latest_two_by_mac(macs)
    syncs = last_syncs(macs)
    readings = last_readings(Enum.map(nodes, & &1.id))

    Map.new(nodes, fn node ->
      {latest, previous} =
        case Map.get(reports, node.mac, []) do
          [latest, previous | _] -> {latest, previous}
          [latest] -> {latest, nil}
          [] -> {nil, nil}
        end

      last_reading_at = Map.get(readings, node.id)
      last_sync_at = Map.get(syncs, node.mac)

      summary = %{
        latest: latest,
        previous: previous,
        last_reading_at: last_reading_at,
        last_seen_at: latest_of([last_reading_at, latest && latest.reported_at]),
        last_sync_at: last_sync_at,
        alerts: []
      }

      {node.id, %{summary | alerts: alerts(summary, now)}}
    end)
  end

  @doc "Alerts for a summary: `:low_battery`, `:storage_almost_full`, `:sync_overdue`, `:clock_not_set`."
  def alerts(%{latest: nil}, _now), do: []

  def alerts(%{latest: report} = summary, now) do
    [
      (report.battery_percent != nil and report.battery_percent < @low_battery_percent) &&
        :low_battery,
      storage_ratio(report) > @storage_full_ratio && :storage_almost_full,
      sync_overdue?(report, summary.last_sync_at, now) && :sync_overdue,
      report.clock_valid == false && :clock_not_set
    ]
    |> Enum.filter(& &1)
  end

  @doc "Fraction of the data partition in use (0.0 when unknown)."
  def storage_ratio(%{storage_total_bytes: total, storage_free_bytes: free})
      when is_integer(total) and total > 0 and is_integer(free),
      do: (total - free) / total

  def storage_ratio(_), do: 0.0

  # A node that keeps data locally is overdue when it has pending data and was not
  # synchronized in the last N days
  defp sync_overdue?(%{pending: pending}, last_sync_at, now)
       when is_integer(pending) and pending > 0 do
    is_nil(last_sync_at) or DateTime.diff(now, last_sync_at, :day) >= @sync_overdue_days
  end

  defp sync_overdue?(_report, _last_sync_at, _now), do: false

  defp last_syncs(macs) do
    from(s in NodeSyncState, where: s.mac in ^macs, select: {s.mac, s.last_sync_at})
    |> Repo.all()
    |> Map.new()
  end

  # Latest measurement time per node (uses the sensor_id + reading_time index)
  defp last_readings(node_ids) do
    from(r in SensorReading,
      join: s in Sensor,
      on: s.id == r.sensor_id,
      where: s.node_id in ^node_ids,
      group_by: s.node_id,
      select: {s.node_id, max(r.reading_time)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp latest_of(datetimes) do
    datetimes
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end
end
