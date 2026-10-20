defmodule LiveMetricsWeb.DeviceSetupLiveTest do
  use LiveMetricsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LiveMetrics.Models.NodeSensorConfig

  @mac "B4:BF:E9:04:E6:C4"
  @sensor_params %{
    "driver" => "analog",
    "pin" => "32",
    "sensor_type" => "soil_moisture",
    "precision" => "1.0",
    "offset" => "0.0",
    "interval_ms" => "10000"
  }

  defp connect_node(view, node_sensors \\ []) do
    render_hook(view, "serial_connected", %{})
    render_hook(view, "node_identified", %{"mac" => String.downcase(@mac)})
    render_hook(view, "node_sensors", %{"sensors" => node_sensors})
  end

  defp node_entry(config) do
    %{
      "id" => config.id,
      "pin" => config.pin,
      "type" => config.sensor_type,
      "driver" => config.driver,
      "precision" => config.precision,
      "offset" => config.offset,
      "interval" => config.interval_ms
    }
  end

  test "sensors are locked until a node is connected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/setup")

    assert has_element?(view, "#sensors-locked")
    refute has_element?(view, "#sensor-form")
    assert has_element?(view, "#btn-connect:not([disabled])")
  end

  test "identifying the node shows its MAC and the sensor form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/setup")
    connect_node(view)

    assert has_element?(view, "#node-mac", @mac)
    assert has_element?(view, "#sensor-form")
    assert has_element?(view, "#btn-connect[disabled]")
  end

  test "saving a sensor stores it with a system id and sends it to the node", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/setup")
    connect_node(view)

    view |> form("#sensor-form", node_sensor_config: @sensor_params) |> render_submit()

    assert [config] = NodeSensorConfig.list_by_mac(@mac)
    id = config.id

    assert_push_event(view, "serial_commands", %{
      commands: [%{command: "sensor", data: %{action: "add", id: ^id, pin: 32}}]
    })

    assert has_element?(view, "#sync-status-#{id}", "Not on node")

    # The node reports the new sensor back
    render_hook(view, "serial_commands_done", %{"results" => [%{"ok" => true}]})
    render_hook(view, "node_sensors", %{"sensors" => [node_entry(config)]})
    assert has_element?(view, "#sync-status-#{id}", "Synced")
  end

  test "editing a sensor that is on the node sends an update", %{conn: conn} do
    {:ok, config} = NodeSensorConfig.create(@mac, @sensor_params)
    {:ok, view, _html} = live(conn, ~p"/devices/setup")
    connect_node(view, [node_entry(config)])

    view |> element("#edit-sensor-#{config.id}") |> render_click()

    view
    |> form("#sensor-form", node_sensor_config: %{@sensor_params | "interval_ms" => "20000"})
    |> render_submit()

    id = config.id

    assert_push_event(view, "serial_commands", %{
      commands: [%{data: %{action: "update", id: ^id, interval: 20_000}}]
    })
  end

  test "a value changed on the node is flagged as differs", %{conn: conn} do
    {:ok, config} = NodeSensorConfig.create(@mac, @sensor_params)
    {:ok, view, _html} = live(conn, ~p"/devices/setup")
    connect_node(view, [%{node_entry(config) | "pin" => 33}])

    assert has_element?(view, "#sync-status-#{config.id}", "Differs")
  end

  test "delete all removes sensors from the database and the node", %{conn: conn} do
    {:ok, a} = NodeSensorConfig.create(@mac, @sensor_params)
    {:ok, b} = NodeSensorConfig.create(@mac, %{@sensor_params | "pin" => "33"})
    {:ok, view, _html} = live(conn, ~p"/devices/setup")

    # b is only in the database; 999 is only on the node
    orphan = %{node_entry(a) | "id" => 999, "pin" => 34}
    connect_node(view, [node_entry(a), orphan])
    assert has_element?(view, "#orphan-999")

    view |> element("#btn-delete-all") |> render_click()

    assert NodeSensorConfig.list_by_mac(@mac) == []
    assert_push_event(view, "serial_commands", %{commands: commands})
    removed = commands |> Enum.map(& &1.data.id) |> Enum.sort()
    assert removed == Enum.sort([a.id, 999])
    refute b.id in removed
  end

  test "disconnecting hides the sensors again", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/setup")
    connect_node(view)

    render_hook(view, "serial_disconnected", %{"message" => "Disconnected"})

    assert has_element?(view, "#sensors-locked")
    refute has_element?(view, "#node-mac")
  end
end
