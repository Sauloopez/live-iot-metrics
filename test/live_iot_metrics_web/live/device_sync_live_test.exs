defmodule LiveMetricsWeb.DeviceSyncLiveTest do
  # Not async: inserting readings creates TimescaleDB chunks inside the sandbox transaction,
  # and concurrent chunk creation deadlocks
  use LiveMetricsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias LiveMetrics.Sync.Ingest

  @mac "B4:BF:E9:04:E6:C4"
  @t0 1_762_164_450

  defp record(seq, sensor_id, value),
    do: <<0x84, 0x1A, seq::32, 0x1A, @t0 + seq * 60::32, sensor_id, 0xFA, value::float-32>>

  defp chunk(seqs), do: Base.encode64(Enum.map_join(seqs, &record(&1, 1, &1 * 1.0)))

  defp connect_node(view, variant \\ "isolated") do
    render_hook(view, "serial_connected", %{})
    render_hook(view, "node_identified", %{"mac" => String.downcase(@mac), "variant" => variant})

    render_hook(view, "node_sensors", %{
      "sensors" => [%{"id" => 1, "type" => "temperature", "precision" => 1}]
    })
  end

  defp report_node(view, next_seq, acked_seq) do
    render_hook(view, "serial_response", %{
      "ref" => "sync_status",
      "ok" => true,
      "response" => %{
        "s" => "ok",
        "n" => next_seq,
        "a" => acked_seq,
        "pd" => next_seq - 1 - acked_seq
      }
    })

    render_hook(view, "serial_response", %{
      "ref" => "status",
      "ok" => true,
      "response" => %{
        "s" => "ok",
        "c" => %{"t" => @t0, "v" => true},
        "b" => %{"mv" => 3912, "p" => 69},
        "st" => %{
          "n" => next_seq,
          "a" => acked_seq,
          "pd" => 0,
          "f" => 1_048_576,
          "tt" => 2_097_152,
          "fw" => 0
        },
        "pw" => %{"bc" => 10, "aw" => 5000, "rr" => 8}
      }
    })
  end

  test "nothing to extract before connecting", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/sync")
    refute has_element?(view, "#extraction-card")
    assert has_element?(view, "#btn-connect:not([disabled])")
  end

  test "a node without storage is explained", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/sync")
    connect_node(view, "coap")

    assert has_element?(view, "#no-storage")
    refute has_element?(view, "#extraction-card")
  end

  test "identifying a storage node asks for its status and shows it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/sync")
    connect_node(view)

    assert_push_event(view, "serial_request", %{ref: "status", command: %{command: "status"}})
    assert_push_event(view, "serial_request", %{ref: "sync_status"})

    report_node(view, 201, 0)
    assert has_element?(view, "#node-pending", "200")
    assert has_element?(view, "#node-battery", "69%")
    assert has_element?(view, "#node-storage", "50%")
  end

  test "extracts in chunks, confirming each one, then finishes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/sync")
    connect_node(view)
    report_node(view, 6, 0)

    view |> element("#btn-extract") |> render_click()
    assert_push_event(view, "sync_start", %{acked: 0})
    assert has_element?(view, "#btn-stop-sync")

    render_hook(view, "sync_chunk", %{"records" => chunk(1..3), "count" => 3})
    assert_reply(view, %{acked_seq: 3})
    assert has_element?(view, "#progress-saved-label", "3 / 5")

    render_hook(view, "sync_chunk", %{"records" => chunk(4..5), "count" => 2})
    assert_reply(view, %{acked_seq: 5})

    render_hook(view, "sync_done", %{"acked_seq" => 5})
    assert has_element?(view, "#sync-result", "5 saved")
    assert Ingest.acked_seq(@mac) == 5
  end

  test "resumes from what the server already has", %{conn: conn} do
    {:ok, _} = Ingest.ingest(@mac, Base.decode64!(chunk(1..4)), %{})
    {:ok, view, _html} = live(conn, ~p"/devices/sync")
    connect_node(view)
    # The node never received the confirmation of 1..4
    report_node(view, 11, 0)

    assert has_element?(view, "#node-pending", "6")
    view |> element("#btn-extract") |> render_click()
    assert_push_event(view, "sync_start", %{acked: 4})

    # A resend of 3..6 only stores 5 and 6
    render_hook(view, "sync_chunk", %{"records" => chunk(3..6), "count" => 4})
    assert_reply(view, %{acked_seq: 6})
    assert has_element?(view, "#progress-saved-label", "2 / 6")
  end

  test "invalid data is rejected without confirming anything", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/sync")
    connect_node(view)
    report_node(view, 3, 0)
    view |> element("#btn-extract") |> render_click()

    render_hook(view, "sync_chunk", %{"records" => Base.encode64(<<0x84, 0x01>>), "count" => 1})
    assert_reply(view, %{error: _})
    assert Ingest.acked_seq(@mac) == 0
  end

  test "a failure and a disconnection during the extraction are reported", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/sync")
    connect_node(view)
    report_node(view, 3, 0)
    view |> element("#btn-extract") |> render_click()

    render_hook(view, "sync_failed", %{"message" => "too many transmission errors"})
    assert has_element?(view, "#sync-result", "too many transmission errors")

    view |> element("#btn-extract") |> render_click()
    html = render_hook(view, "serial_disconnected", %{"message" => "Device lost"})
    assert html =~ "Extraction interrupted"
    refute has_element?(view, "#extraction-card")
  end

  test "Devices links to the extraction screen", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices")

    {:ok, sync, _html} =
      view |> element("#device-sync-link") |> render_click() |> follow_redirect(conn)

    assert has_element?(sync, "#btn-connect")
  end
end
