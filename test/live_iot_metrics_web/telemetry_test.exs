defmodule LiveMetricsWeb.TelemetryTest do
  use ExUnit.Case, async: true

  test "repo metrics listen to the events the Repo actually emits" do
    prefix = LiveMetrics.Repo.config()[:telemetry_prefix]

    repo_metrics =
      Enum.filter(LiveMetricsWeb.Telemetry.metrics(), &(:repo in &1.event_name))

    assert repo_metrics != []
    assert Enum.all?(repo_metrics, &(&1.event_name == prefix ++ [:query]))
  end
end
