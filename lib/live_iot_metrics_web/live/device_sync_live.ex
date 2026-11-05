defmodule LiveMetricsWeb.DeviceSyncLive do
  @moduledoc """
  Extracts the measurements stored on a node over USB (docs/tundra/PLAN.md, section 6.1).

  The `WebSerialHook` streams the data from the node in batches (`sync_chunk`); each batch is
  stored with `LiveMetrics.Sync.Ingest` and the reply carries the new watermark, which the
  hook forwards to the node so it can release that data. Only the server confirms.
  """
  use LiveMetricsWeb, :live_view

  alias LiveMetrics.Health.NodeStatusReport
  alias LiveMetrics.Sync.Ingest

  @storage_variants ~w(isolated)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Extract data")
     |> assign(:serial_supported?, true)
     |> reset_node()}
  end

  defp reset_node(socket) do
    socket
    |> assign(:connected?, false)
    |> assign(:mac, nil)
    |> assign(:variant, nil)
    |> assign(:node_status, nil)
    |> assign(:node_sync, nil)
    |> assign(:server_acked, 0)
    |> assign(:sensors, %{})
    |> assign(:sync, idle_sync())
  end

  defp idle_sync do
    %{
      state: :idle,
      total: 0,
      received: 0,
      stored: 0,
      ignored: 0,
      skipped: 0,
      start_acked: 0,
      acked: 0,
      started_at: nil,
      finished_at: nil,
      error: nil
    }
  end

  # --- Serial transport events (from WebSerialHook) ---

  @impl true
  def handle_event("serial_unsupported", _params, socket) do
    {:noreply, assign(socket, :serial_supported?, false)}
  end

  def handle_event("serial_connected", _params, socket) do
    {:noreply, socket |> clear_flash() |> assign(:connected?, true)}
  end

  def handle_event("serial_disconnected", %{"message" => message}, socket) do
    socket =
      if socket.assigns.sync.state == :running,
        do:
          put_flash(
            socket,
            :error,
            "Extraction interrupted: #{message}. Connect again to resume."
          ),
        else: put_flash(socket, :info, message)

    {:noreply, reset_node(socket)}
  end

  def handle_event("node_identified", %{"mac" => mac} = params, socket) do
    mac = String.upcase(mac)

    {:noreply,
     socket
     |> assign(:mac, mac)
     |> assign(:variant, params["variant"])
     |> assign(:server_acked, Ingest.acked_seq(mac))
     |> request_node_status()}
  end

  def handle_event("node_error", %{"message" => message}, socket) do
    {:noreply, put_flash(socket, :error, "Could not identify the node: #{message}")}
  end

  def handle_event("node_sensors", %{"sensors" => sensors}, socket) do
    meta =
      Map.new(sensors, fn s ->
        {s["id"],
         %{type: s["type"] || "sensor_#{s["id"]}", precision: (s["precision"] || 1) * 1.0}}
      end)

    {:noreply, assign(socket, :sensors, meta)}
  end

  def handle_event("serial_response", %{"ref" => "status", "ok" => true, "response" => r}, socket) do
    NodeStatusReport.record(socket.assigns.mac, socket.assigns.variant, "usb", r)
    {:noreply, assign(socket, :node_status, r)}
  end

  def handle_event(
        "serial_response",
        %{"ref" => "sync_status", "ok" => true, "response" => r},
        socket
      ) do
    {:noreply, assign(socket, :node_sync, %{next: r["n"], acked: r["a"], pending: r["pd"]})}
  end

  def handle_event("serial_response", _params, socket), do: {:noreply, socket}

  # --- Extraction ---

  def handle_event("extract", _params, socket) do
    %{server_acked: server_acked, node_sync: node_sync} = socket.assigns
    acked = max(server_acked, node_sync.acked)

    sync = %{
      idle_sync()
      | state: :running,
        total: max(node_sync.next - 1 - acked, 0),
        start_acked: acked,
        acked: acked,
        started_at: System.monotonic_time(:millisecond)
    }

    {:noreply,
     socket
     |> clear_flash()
     |> assign(:sync, sync)
     |> push_event("sync_start", %{acked: acked})}
  end

  def handle_event("stop_sync", _params, socket) do
    {:noreply,
     socket
     |> update(:sync, &%{&1 | state: :idle})
     |> push_event("sync_stop", %{})}
  end

  def handle_event("sync_chunk", %{"records" => records, "count" => count}, socket) do
    with {:ok, binary} <- Base.decode64(records),
         {:ok, result} <- Ingest.ingest(socket.assigns.mac, binary, socket.assigns.sensors) do
      sync =
        socket.assigns.sync
        |> Map.update!(:received, &(&1 + count))
        |> Map.update!(:stored, &(&1 + result.stored))
        |> Map.update!(:ignored, &(&1 + result.ignored))
        |> Map.update!(:skipped, &(&1 + result.skipped_without_time))
        |> Map.put(:acked, result.acked_seq)

      {:reply, %{acked_seq: result.acked_seq},
       socket |> assign(:sync, sync) |> assign(:server_acked, result.acked_seq)}
    else
      {:error, reason} ->
        {:reply, %{error: format_error(reason)}, socket}

      :error ->
        {:reply, %{error: "invalid base64"}, socket}
    end
  end

  def handle_event("sync_done", %{"acked_seq" => acked}, socket) do
    sync = %{
      socket.assigns.sync
      | state: :done,
        acked: acked,
        finished_at: System.monotonic_time(:millisecond)
    }

    {:noreply,
     socket
     |> assign(:sync, sync)
     |> put_flash(:info, "Extraction finished: #{sync.stored} measurement(s) saved")
     |> request_node_status()}
  end

  def handle_event("sync_failed", %{"message" => message}, socket) do
    {:noreply,
     socket
     |> update(:sync, &%{&1 | state: :failed, error: message})
     |> put_flash(:error, "Extraction stopped: #{message}")
     |> request_node_status()}
  end

  # --- Helpers ---

  defp request_node_status(%{assigns: %{variant: variant}} = socket)
       when variant in @storage_variants do
    socket
    |> push_event("serial_request", %{ref: "status", command: %{command: "status"}})
    |> push_event("serial_request", %{
      ref: "sync_status",
      command: %{command: "sync", data: %{action: "status"}}
    })
  end

  defp request_node_status(socket), do: socket

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp storage_node?(variant), do: variant in @storage_variants

  defp percent(_part, 0), do: 0
  defp percent(part, total), do: min(round(part * 100 / total), 100)

  defp saved(sync), do: sync.acked - sync.start_acked

  defp elapsed_s(%{started_at: nil}), do: 0

  defp elapsed_s(sync) do
    ((sync.finished_at || System.monotonic_time(:millisecond)) - sync.started_at) / 1000
  end

  defp rate(sync) do
    seconds = elapsed_s(sync)
    if seconds > 0, do: saved(sync) / seconds, else: 0.0
  end

  defp eta(sync) do
    r = rate(sync)
    remaining = sync.total - saved(sync)
    if r > 0 and remaining > 0, do: "#{round(remaining / r)} s", else: "—"
  end

  defp format_bytes(nil), do: "—"
  defp format_bytes(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 2)} MB"
  defp format_bytes(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"

  defp format_clock(%{"t" => t, "v" => true}) when is_integer(t) and t > 0 do
    t |> DateTime.from_unix!() |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_clock(_), do: "Not set"

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="device-sync" class="space-y-6" phx-hook="WebSerialHook">
        <div class="flex items-center gap-3">
          <.button navigate={~p"/devices"} class="btn btn-ghost btn-sm" id="back-to-devices">
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Devices
          </.button>
          <div>
            <h1 class="text-3xl font-bold text-primary">Extract data</h1>
            <p class="text-sm text-base-content/60">
              Wake the node with its BOOT button, connect it over USB and download what it stored.
              The node only deletes data once the server has saved it.
            </p>
          </div>
        </div>

        <%!-- Connection --%>
        <section
          id="connection-card"
          class={[
            "rounded-box border p-4 flex flex-wrap items-center justify-between gap-4 transition-colors",
            if(@connected?, do: "border-success/40 bg-success/5", else: "border-base-300 bg-base-200")
          ]}
        >
          <div class="leading-tight">
            <p id="connection-status" class="font-semibold">
              <%= cond do %>
                <% not @serial_supported? -> %>
                  Web Serial not supported in this browser
                <% @connected? and @mac -> %>
                  Connected
                <% @connected? -> %>
                  Connected · identifying node…
                <% true -> %>
                  Not connected
              <% end %>
            </p>
            <p :if={@mac} id="node-mac" class="font-mono text-xs text-base-content/60">
              {@mac} · {@variant || "unknown firmware"}
            </p>
          </div>
          <div class="flex gap-2">
            <.button
              id="btn-connect"
              type="button"
              data-serial-action="connect"
              class="btn btn-primary btn-sm"
              disabled={@connected? or not @serial_supported?}
            >
              <.icon name="hero-bolt" class="w-4 h-4" /> Connect to device
            </.button>
            <.button
              id="btn-disconnect"
              type="button"
              data-serial-action="disconnect"
              class="btn btn-ghost btn-sm"
              disabled={not @connected? or @sync.state == :running}
            >
              Disconnect
            </.button>
          </div>
        </section>

        <div
          :if={@mac && not storage_node?(@variant)}
          id="no-storage"
          class="alert alert-info"
        >
          <.icon name="hero-information-circle" class="w-5 h-5" />
          <span>
            This node ({@variant || "unknown firmware"}) sends its measurements as it takes them and
            stores nothing to extract.
          </span>
        </div>

        <%!-- Node summary --%>
        <section
          :if={@mac && storage_node?(@variant)}
          id="node-summary"
          class="grid grid-cols-2 md:grid-cols-4 gap-4"
        >
          <div class="rounded-box bg-base-200 p-4">
            <p class="text-xs text-base-content/60">Pending on the node</p>
            <p id="node-pending" class="text-2xl font-bold tabular-nums">
              {if @node_sync,
                do: max(@node_sync.next - 1 - max(@server_acked, @node_sync.acked), 0),
                else: "—"}
            </p>
            <p class="text-xs text-base-content/50">
              server has up to seq {@server_acked}
            </p>
          </div>
          <div class="rounded-box bg-base-200 p-4">
            <p class="text-xs text-base-content/60">Battery</p>
            <p id="node-battery" class="text-2xl font-bold tabular-nums">
              {if @node_status, do: "#{@node_status["b"]["p"]}%", else: "—"}
            </p>
            <p class="text-xs text-base-content/50">
              {if @node_status, do: "#{@node_status["b"]["mv"]} mV", else: ""}
            </p>
          </div>
          <div class="rounded-box bg-base-200 p-4">
            <p class="text-xs text-base-content/60">Storage used</p>
            <p id="node-storage" class="text-2xl font-bold tabular-nums">
              <%= if @node_status do %>
                {percent(@node_status["st"]["tt"] - @node_status["st"]["f"], @node_status["st"]["tt"])}%
              <% else %>
                —
              <% end %>
            </p>
            <p class="text-xs text-base-content/50">
              {if @node_status, do: "#{format_bytes(@node_status["st"]["f"])} free", else: ""}
            </p>
          </div>
          <div class="rounded-box bg-base-200 p-4">
            <p class="text-xs text-base-content/60">Node clock</p>
            <p id="node-clock" class="text-sm font-semibold font-mono mt-2">
              {if @node_status, do: format_clock(@node_status["c"]), else: "—"}
            </p>
            <p class="text-xs text-base-content/50">corrected after each extraction</p>
          </div>
        </section>

        <%!-- Extraction --%>
        <section
          :if={@mac && storage_node?(@variant)}
          id="extraction-card"
          class="card bg-base-200 p-4 space-y-4"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="font-bold text-lg flex items-center gap-2">
              <.icon name="hero-arrow-down-tray" class="w-5 h-5 text-accent" /> Extraction
            </h2>
            <div class="flex gap-2">
              <.button
                :if={@sync.state != :running}
                id="btn-extract"
                type="button"
                phx-click="extract"
                class="btn btn-primary btn-sm"
                disabled={is_nil(@node_sync)}
              >
                <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Extract data
              </.button>
              <.button
                :if={@sync.state == :running}
                id="btn-stop-sync"
                type="button"
                phx-click="stop_sync"
                class="btn btn-ghost btn-sm"
              >
                Stop
              </.button>
            </div>
          </div>

          <div :if={@sync.state != :idle} class="space-y-3">
            <div>
              <div class="flex justify-between text-xs mb-1">
                <span>Received from the node</span>
                <span id="progress-received-label" class="tabular-nums">
                  {@sync.received} / {@sync.total}
                </span>
              </div>
              <progress
                id="progress-received"
                class="progress progress-info w-full"
                value={percent(@sync.received, @sync.total)}
                max="100"
              >
              </progress>
            </div>
            <div>
              <div class="flex justify-between text-xs mb-1">
                <span>Saved on the server (the node can release it)</span>
                <span id="progress-saved-label" class="tabular-nums">
                  {saved(@sync)} / {@sync.total}
                </span>
              </div>
              <progress
                id="progress-saved"
                class="progress progress-success w-full"
                value={percent(saved(@sync), @sync.total)}
                max="100"
              >
              </progress>
            </div>
            <p class="text-xs text-base-content/60 tabular-nums">
              {Float.round(rate(@sync), 1)} measurements/s · remaining {eta(@sync)}
            </p>
          </div>

          <div
            :if={@sync.state in [:done, :failed]}
            id="sync-result"
            class={[
              "rounded-box p-3 text-sm",
              if(@sync.state == :done, do: "bg-success/10", else: "bg-error/10")
            ]}
          >
            <p class="font-semibold">
              {if @sync.state == :done, do: "Extraction finished", else: "Extraction stopped"}
            </p>
            <p :if={@sync.error}>{@sync.error}</p>
            <p>
              {@sync.stored} saved · {@sync.ignored} already on the server · {@sync.skipped} without a valid time
            </p>
          </div>
        </section>

        <%!-- Terminal --%>
        <section class="card bg-base-200 p-4">
          <div class="flex items-center justify-between mb-2">
            <h2 class="font-bold flex items-center gap-2">
              <.icon name="hero-command-line" class="w-4 h-4" /> Terminal
            </h2>
            <.button
              id="btn-clear-terminal"
              type="button"
              data-serial-action="clear-terminal"
              class="btn btn-ghost btn-xs"
            >
              Clear
            </.button>
          </div>
          <pre
            id="serial-terminal"
            phx-update="ignore"
            class="bg-black text-green-400 p-3 h-48 overflow-y-auto text-xs rounded font-mono whitespace-pre-wrap break-all"
          ></pre>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
