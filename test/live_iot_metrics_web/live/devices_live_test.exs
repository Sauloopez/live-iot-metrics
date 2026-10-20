defmodule LiveMetricsWeb.DevicesLiveTest do
  use LiveMetricsWeb.ConnCase, async: true

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
end
