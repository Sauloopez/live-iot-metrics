defmodule LiveMetricsWeb.DevicesLiveTest do
  use LiveMetricsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LiveMetrics.Area
  alias LiveMetrics.Nodes
  alias LiveMetrics.Sensor

  defp create_fixtures(_) do
    {:ok, area} = Area.create_area(%{name: "Main Area", description: "The main area"})
    {:ok, node} = Nodes.get_or_insert("AA:BB:CC:DD:EE:FF")
    {:ok, sensor} = Sensor.update_or_create(node, 1, "temperature", 0.1)

    %{area: area, node: node, sensor: sensor}
  end

  defp format_mac(mac) do
    mac |> Base.encode16() |> to_charlist() |> Enum.chunk_every(2) |> Enum.join(":")
  end

  describe "Devices page" do
    setup [:create_fixtures]

    test "renders devices list", %{conn: conn, node: node} do
      {:ok, _view, html} = live(conn, ~p"/devices")

      assert html =~ "Devices"
      assert html =~ node.name
      assert html =~ format_mac(node.mac)
      assert html =~ "Unassigned"
    end

    test "opens edit modal and shows sensor info", %{conn: conn, node: _node, sensor: sensor} do
      {:ok, view, _html} = live(conn, ~p"/devices")

      html = view |> element("button", "Edit") |> render_click()

      assert html =~ "Edit Device"
      assert html =~ "MAC Address (Read-only)"
      # Sensor info should be visible
      assert html =~ sensor.sensor_type
      assert html =~ to_string(sensor.node_sensor_id)
    end

    test "validates form data", %{conn: conn, node: _node} do
      {:ok, view, _html} = live(conn, ~p"/devices")

      view |> element("button", "Edit") |> render_click()

      html =
        view
        |> form("form[phx-change=validate]", %{"nodes" => %{"name" => ""}})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "updates device successfully", %{conn: conn, area: area} do
      {:ok, view, _html} = live(conn, ~p"/devices")

      view |> element("button", "Edit") |> render_click()

      html =
        view
        |> form("form[phx-submit=save]", %{
          "nodes" => %{
            "name" => "Updated Node Name",
            "description" => "New description",
            "area_id" => area.id
          }
        })
        |> render_submit()

      assert html =~ "Updated Node Name"
      assert html =~ "New description"
      assert html =~ area.name
    end
  end
end
