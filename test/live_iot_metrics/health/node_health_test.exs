defmodule LiveMetrics.Health.NodeHealthTest do
  # Not async: inserting readings creates TimescaleDB chunks inside the sandbox transaction,
  # and concurrent chunk creation deadlocks
  use LiveMetrics.DataCase, async: false

  import LiveMetrics.Fixtures

  alias LiveMetrics.Health.{NodeHealth, NodeStatusReport}
  alias LiveMetrics.Models.Nodes
  alias LiveMetrics.Sync.NodeSyncState

  # A `status` response as the node sends it (short keys, docs/tundra/SERIAL_API.md)
  defp status(attrs \\ %{}) do
    %{
      "s" => "ok",
      "c" => %{"t" => 1_762_164_450, "v" => Map.get(attrs, :clock_valid, true)},
      "b" => %{"mv" => Map.get(attrs, :mv, 3912), "p" => Map.get(attrs, :percent, 69)},
      "st" => %{
        "n" => 1201,
        "a" => 1000,
        "pd" => Map.get(attrs, :pending, 200),
        "f" => Map.get(attrs, :free, 1_048_576),
        "tt" => 2_097_152,
        "fw" => 0
      },
      "pw" => %{"bc" => 96, "aw" => 153_000, "rr" => 8}
    }
  end

  defp summary_for(node, now \\ DateTime.utc_now()) do
    node = Repo.get_by!(Nodes, mac: node.mac)
    Map.fetch!(NodeHealth.summaries([node], now), node.id)
  end

  describe "NodeStatusReport.record/4" do
    test "stores the short-key status and registers an unknown node" do
      mac = unique_mac()
      refute Repo.get_by(Nodes, mac: mac)

      {:ok, report} = NodeStatusReport.record(String.downcase(mac), "isolated", "usb", status())

      assert report.mac == mac
      assert {report.battery_mv, report.battery_percent} == {3912, 69}
      assert {report.next_seq, report.acked_seq, report.pending} == {1201, 1000, 200}
      assert {report.boot_count, report.reset_reason} == {96, 8}
      assert report.clock_valid
      assert Repo.get_by(Nodes, mac: mac)
    end

    test "missing sections are stored as unknown" do
      {:ok, report} = NodeStatusReport.record(unique_mac(), "isolated", "usb", %{"s" => "ok"})
      assert is_nil(report.battery_mv)
      refute report.clock_valid
    end

    test "latest_two_by_mac/1 returns the newest reports first" do
      node = node_fixture()
      {:ok, _} = NodeStatusReport.record(node.mac, "isolated", "usb", status(%{mv: 3900}))
      {:ok, _} = NodeStatusReport.record(node.mac, "isolated", "usb", status(%{mv: 3950}))
      {:ok, _} = NodeStatusReport.record(node.mac, "isolated", "usb", status(%{mv: 4000}))

      assert [%{battery_mv: 4000}, %{battery_mv: 3950}] =
               NodeStatusReport.latest_two_by_mac([node.mac])[node.mac]
    end
  end

  describe "NodeHealth.summaries/2" do
    test "a healthy node has no alerts and is seen at its last report" do
      node = node_fixture()
      {:ok, report} = NodeStatusReport.record(node.mac, "isolated", "usb", status(%{pending: 0}))

      summary = summary_for(node)
      assert summary.alerts == []
      assert summary.latest.id == report.id
      assert summary.last_seen_at == report.reported_at
    end

    test "last seen is the newest of measurements and reports" do
      node = node_fixture()
      readings_fixture(sensor_fixture(node), [20.0])
      summary = summary_for(node)
      assert summary.last_reading_at
      assert summary.last_seen_at == summary.last_reading_at
    end

    test "flags low battery, full storage and an unset clock" do
      node = node_fixture()

      {:ok, _} =
        NodeStatusReport.record(
          node.mac,
          "isolated",
          "usb",
          status(%{percent: 12, free: 100_000, clock_valid: false, pending: 0})
        )

      assert Enum.sort(summary_for(node).alerts) == [
               :clock_not_set,
               :low_battery,
               :storage_almost_full
             ]
    end

    test "pending data without a recent sync is overdue" do
      node = node_fixture()
      {:ok, _} = NodeStatusReport.record(node.mac, "isolated", "usb", status(%{pending: 50}))
      assert :sync_overdue in summary_for(node).alerts

      Repo.insert!(%NodeSyncState{mac: node.mac, last_sync_at: DateTime.utc_now()})
      refute :sync_overdue in summary_for(node).alerts

      eight_days_later = DateTime.add(DateTime.utc_now(), 8, :day)
      assert :sync_overdue in summary_for(node, eight_days_later).alerts
    end

    test "nodes that never reported have no health data" do
      node = node_fixture()
      assert %{latest: nil, alerts: [], last_seen_at: nil} = summary_for(node)
    end
  end
end
