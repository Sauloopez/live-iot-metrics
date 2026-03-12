defmodule LiveMetricsWeb.DashboardLiveTest do
  use LiveMetricsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias LiveMetrics.Area
  alias LiveMetrics.Nodes
  alias LiveMetrics.Repo

  defp create_area(_) do
    {:ok, area} = Area.create_area(%{name: "Test Area", description: "Test Description"})
    %{area: area}
  end

  defp create_node(_) do
    {:ok, node} = Nodes.get_or_insert("00:1A:2B:3C:4D:5E")
    %{node: node}
  end

  defp format_mac(mac) do
    mac |> Base.encode16() |> to_charlist() |> Enum.chunk_every(2) |> Enum.join(":")
  end

  describe "Dashboard without areas" do
    test "renders empty state when no areas exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "No Areas Yet"
      assert html =~ "Get started by creating your first tracking area"
      assert html =~ "Create Area"
    end

    test "can open create area modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert view |> element("button", "Create Area") |> render_click() =~ "Add New Area"
      assert has_element?(view, "form[phx-submit=save_area]")
    end

    test "can create an area", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("button", "Create Area") |> render_click()

      # Submit the form
      html =
        view
        |> form("form[phx-submit=save_area]", %{name: "New Area", description: "A new area"})
        |> render_submit()

      assert html =~ "New Area"
      refute html =~ "No Areas Yet"
    end
  end

  describe "Dashboard with areas" do
    setup [:create_area]

    test "renders tabs for areas", %{conn: conn, area: area} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ area.name
      assert html =~ "Area Devices"
    end

    test "renders area details", %{conn: conn, area: area} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ area.name
      assert html =~ "No devices assigned to this area"
    end

    test "can switch between areas", %{conn: conn, area: area1} do
      {:ok, area2} = Area.create_area(%{name: "Second Area", description: "Second Description"})

      {:ok, view, _html} = live(conn, ~p"/")

      # Initially on first area
      assert view |> element("a.tab-active") |> render() =~ area1.name

      # Switch to second area
      html = view |> element("a", area2.name) |> render_click()

      assert html =~ "tab-active"
      assert view |> element("a.tab-active") |> render() =~ area2.name
    end

    test "can change time interval", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "button.btn-active[phx-value-interval=last_hour]")

      _html = view |> element("button[phx-value-interval=last_day]") |> render_click()

      assert has_element?(view, "button.btn-active[phx-value-interval=last_day]")
    end
  end

  describe "Dashboard with devices" do
    setup [:create_area, :create_node]

    test "can open assign device modal", %{conn: conn, area: _area, node: node} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert view |> element("button", "Add Device") |> render_click() =~ "Assign Devices to Area"
      assert has_element?(view, "form[phx-submit=save_nodes]")

      # Node should be listed
      modal_html = view |> element("form[phx-submit=save_nodes]") |> render()
      assert modal_html =~ node.name
      assert modal_html =~ format_mac(node.mac)
    end

    test "can assign device to area", %{conn: conn, area: _area, node: node} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("button", "Add Device") |> render_click()

      # Assign the node
      _html =
        view
        |> form("form[phx-submit=save_nodes]", %{"node_ids" => [node.id]})
        |> render_submit()

      # Device should now be visible in the area view
      assert has_element?(view, ".card", node.name)
      assert has_element?(view, ".card", format_mac(node.mac))

      # Double check database
      updated_node = Repo.get(Nodes, node.id)
      assert updated_node.area_id != nil
    end

    test "renders assigned devices", %{conn: conn, area: area, node: node} do
      # Pre-assign node
      Repo.update_all(from(n in Nodes, where: n.id == ^node.id), set: [area_id: area.id])

      {:ok, _view, html} = live(conn, ~p"/")

      # Should not show empty state
      refute html =~ "No devices assigned to this area"

      # Should show the device
      assert html =~ node.name
      assert html =~ format_mac(node.mac)
    end
  end
end
