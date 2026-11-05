defmodule LiveMetricsWeb.DevicesLiveTest do
  use LiveMetricsWeb.ConnCase, async: true

  alias LiveMetrics.Health.NodeStatusReport

  import Phoenix.LiveViewTest
  import LiveMetrics.Fixtures

  test "shows an empty state without nodes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices")
    refute has_element?(view, "#nodes-table")
  end

  describe "with nodes" do
    setup do
      node = node_fixture(name: "Greenhouse node")
      light = sensor_fixture(node, node_sensor_id: 1, sensor_type: "light")
      sensor_fixture(node, node_sensor_id: 2, sensor_type: "light")
      sensor_fixture(node, node_sensor_id: 3, sensor_type: "soil_moisture")
      %{node: node, light: light}
    end

    test "lists nodes with their MAC and sensor counts by type", %{conn: conn, node: node} do
      {:ok, view, _html} = live(conn, ~p"/devices")

      assert has_element?(view, "#nodes-table", "Greenhouse node")
      assert has_element?(view, "#nodes-table", node.mac)
      assert has_element?(view, "#nodes-table", "light: 2")
      assert has_element?(view, "#nodes-table", "soil_moisture: 1")
    end

    test "manage shows the node sensors and toggles recording", %{
      conn: conn,
      node: node,
      light: light
    } do
      {:ok, view, _html} = live(conn, ~p"/devices")

      view |> element("#manage-node-#{node.id}") |> render_click()
      assert has_element?(view, "#node-modal", node.mac)
      assert has_element?(view, "#node-modal-sensors", "soil_moisture")

      view |> element("#toggle-sensor-#{light.id}") |> render_click()
      assert has_element?(view, "#node-modal-sensors", "Inactive since")
      refute LiveMetrics.Repo.reload!(light).active

      view |> element("#toggle-sensor-#{light.id}") |> render_click()
      assert LiveMetrics.Repo.reload!(light).active
    end
  end

  test "configure via USB opens the device setup screen", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices")

    {:ok, setup, _html} =
      view |> element("#device-setup-link") |> render_click() |> follow_redirect(conn)

    assert has_element?(setup, "#btn-connect")
  end

  describe "health" do
    setup do
      node = node_fixture(name: "Paramo node")

      status = fn percent, mv ->
        %{
          "s" => "ok",
          "c" => %{"t" => 1_762_164_450, "v" => true},
          "b" => %{"mv" => mv, "p" => percent},
          "st" => %{
            "n" => 101,
            "a" => 50,
            "pd" => 50,
            "f" => 100_000,
            "tt" => 2_097_152,
            "fw" => 0
          },
          "pw" => %{"bc" => 3, "aw" => 1000, "rr" => 8}
        }
      end

      {:ok, _} = NodeStatusReport.record(node.mac, "isolated", "usb", status.(30, 3750))
      {:ok, _} = NodeStatusReport.record(node.mac, "isolated", "usb", status.(15, 3600))
      %{node: node}
    end

    test "shows battery with its trend, storage, last seen and alerts", %{conn: conn, node: node} do
      {:ok, view, _html} = live(conn, ~p"/devices")

      assert has_element?(view, "#battery-#{node.id}", "15%")
      assert has_element?(view, "#storage-#{node.id}", "50 pending")
      assert has_element?(view, "#last-seen-#{node.id}", "just now")
      assert has_element?(view, "#alerts-#{node.id}-low_battery", "Low battery")
      assert has_element?(view, "#alerts-#{node.id}-storage_almost_full")
      assert has_element?(view, "#alerts-#{node.id}-sync_overdue")
    end

    test "the node modal lists the recent reports", %{conn: conn, node: node} do
      {:ok, view, _html} = live(conn, ~p"/devices")
      view |> element("#manage-node-#{node.id}") |> render_click()

      assert has_element?(view, "#node-health-reports", "3600 mV")
      assert has_element?(view, "#node-health-reports", "3750 mV")
    end
  end

  test "nodes without reports show no health data", %{conn: conn} do
    node = node_fixture()
    {:ok, view, _html} = live(conn, ~p"/devices")
    assert has_element?(view, "#battery-#{node.id}", "—")
    assert has_element?(view, "#last-seen-#{node.id}", "never")

    view |> element("#manage-node-#{node.id}") |> render_click()
    assert has_element?(view, "#node-health-empty")
  end
end
