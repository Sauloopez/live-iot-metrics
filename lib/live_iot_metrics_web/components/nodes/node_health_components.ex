defmodule LiveMetricsWeb.Components.NodeHealthComponents do
  @moduledoc """
  Pieces that show the health of a node (`LiveMetrics.Health.NodeHealth` summaries) in the
  Devices table and the node modal.
  """
  use LiveMetricsWeb, :html

  alias LiveMetrics.Health.NodeHealth

  @doc "Battery percent with a trend arrow against the previous report."
  attr :id, :string, required: true
  attr :latest, :any, default: nil
  attr :previous, :any, default: nil

  def battery(assigns) do
    assigns = assign(assigns, :trend, battery_trend(assigns.latest, assigns.previous))

    ~H"""
    <span
      :if={is_nil(@latest) or is_nil(@latest.battery_percent)}
      id={@id}
      class="text-base-content/40"
    >
      —
    </span>
    <span
      :if={@latest && @latest.battery_percent}
      id={@id}
      class={[
        "inline-flex items-center gap-1 tabular-nums",
        @latest.battery_percent < NodeHealth.thresholds().low_battery_percent &&
          "text-error font-semibold"
      ]}
      title={"#{@latest.battery_mv} mV"}
    >
      <.icon name={battery_icon(@latest.battery_percent)} class="w-4 h-4" />
      {@latest.battery_percent}%
      <.icon :if={@trend == :up} name="hero-arrow-trending-up-mini" class="w-4 h-4 text-success" />
      <.icon :if={@trend == :down} name="hero-arrow-trending-down-mini" class="w-4 h-4 text-warning" />
    </span>
    """
  end

  @doc "Relative time (\"5 min ago\"), with the exact UTC time on hover."
  attr :id, :string, required: true
  attr :at, :any, default: nil
  attr :now, :any, required: true

  def ago(assigns) do
    ~H"""
    <span :if={is_nil(@at)} id={@id} class="text-base-content/40">never</span>
    <span
      :if={@at}
      id={@id}
      class="whitespace-nowrap"
      title={Calendar.strftime(@at, "%Y-%m-%d %H:%M:%S UTC")}
    >
      {format_ago(@at, @now)}
    </span>
    """
  end

  @doc "Storage use of nodes that keep data locally, with what is still pending."
  attr :id, :string, required: true
  attr :latest, :any, default: nil

  def storage(assigns) do
    ~H"""
    <span
      :if={is_nil(@latest) or is_nil(@latest.storage_total_bytes)}
      id={@id}
      class="text-base-content/40"
    >
      —
    </span>
    <span :if={@latest && @latest.storage_total_bytes} id={@id} class="tabular-nums whitespace-nowrap">
      {round(NodeHealth.storage_ratio(@latest) * 100)}% · {@latest.pending || 0} pending
    </span>
    """
  end

  @doc "Alert badges; each one pairs an icon with a label so color is never the only cue."
  attr :id, :string, required: true
  attr :alerts, :list, default: []

  def alerts(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col items-start gap-1">
      <span
        :for={alert <- @alerts}
        id={"#{@id}-#{alert}"}
        class={["badge badge-sm badge-soft gap-1 whitespace-nowrap", alert_class(alert)]}
      >
        <.icon name={alert_icon(alert)} class="w-3.5 h-3.5" /> {alert_label(alert)}
      </span>
      <span :if={@alerts == []} class="text-base-content/40 text-sm">—</span>
    </div>
    """
  end

  def format_ago(at, now) do
    seconds = max(DateTime.diff(now, at, :second), 0)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)} min ago"
      seconds < 86_400 -> "#{div(seconds, 3600)} h ago"
      true -> "#{div(seconds, 86_400)} d ago"
    end
  end

  defp battery_trend(%{battery_mv: now}, %{battery_mv: before})
       when is_integer(now) and is_integer(before) do
    # Small changes are ADC noise, not a trend
    cond do
      now - before > 20 -> :up
      before - now > 20 -> :down
      true -> :flat
    end
  end

  defp battery_trend(_latest, _previous), do: :flat

  defp battery_icon(percent) when percent < 20, do: "hero-battery-0"
  defp battery_icon(percent) when percent < 70, do: "hero-battery-50"
  defp battery_icon(_percent), do: "hero-battery-100"

  defp alert_label(:low_battery), do: "Low battery"
  defp alert_label(:storage_almost_full), do: "Storage almost full"
  defp alert_label(:sync_overdue), do: "Sync overdue"
  defp alert_label(:clock_not_set), do: "Clock not set"

  defp alert_icon(:low_battery), do: "hero-battery-0"
  defp alert_icon(:storage_almost_full), do: "hero-circle-stack"
  defp alert_icon(:sync_overdue), do: "hero-clock"
  defp alert_icon(:clock_not_set), do: "hero-exclamation-triangle"

  defp alert_class(:low_battery), do: "badge-error"
  defp alert_class(:storage_almost_full), do: "badge-warning"
  defp alert_class(:sync_overdue), do: "badge-warning"
  defp alert_class(:clock_not_set), do: "badge-warning"
end
