defmodule LiveMetricsWeb.RecipeBatchLiveTest do
  use LiveMetricsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LiveMetrics.Fixtures

  alias LiveMetrics.Models.BatchSensor

  setup do
    recipe = recipe_fixture(name: "Basil", ranges: [{"light", 30, 90}, {"soil_moisture", 20, 80}])
    batch = batch_fixture(area_fixture(), recipe, name: "Basil batch")
    node = node_fixture(name: "Greenhouse node")
    light = sensor_fixture(node, node_sensor_id: 1, sensor_type: "light")
    %{recipe: recipe, batch: batch, node: node, light: light}
  end

  defp reading(sensor, value) do
    %{
      "sensor_id" => sensor.id,
      "value" => value,
      "reading_time" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  test "an unknown batch shows not found", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/recipe-batch/#{Ecto.UUID.generate()}")
    assert has_element?(view, "#batch-not-found")
  end

  test "attaches a node, tracking only sensors with a recipe range", %{
    conn: conn,
    batch: batch,
    node: node,
    light: light
  } do
    unknown = sensor_fixture(node, node_sensor_id: 2, sensor_type: "co2")
    {:ok, view, _html} = live(conn, ~p"/recipe-batch/#{batch.id}")

    view |> element("#btn-attach-node") |> render_click()
    view |> form("#select-node-form", %{node_id: node.id}) |> render_change()

    # Sensors without a matching recipe range can not be selected
    assert has_element?(view, "#attach-node-form input[value='#{unknown.id}'][disabled]")
    assert has_element?(view, "#attach-node-form input[value='#{light.id}'][checked]")

    view |> form("#attach-node-form", %{sensor_ids: [light.id]}) |> render_submit()

    assert render(view) =~ "Node attached to batch"
    assert has_element?(view, "#tracked-node-#{node.id}", "Greenhouse node")

    assert [%{sensor_id: sensor_id, min_value: 30.0, max_value: 90.0}] =
             LiveMetrics.Repo.all(BatchSensor)

    assert sensor_id == light.id
  end

  describe "with a tracked sensor" do
    setup %{batch: batch, light: light} do
      readings_fixture(light, [40.0, 50.0, 60.0])
      %{batch_sensor: batch_sensor_fixture(batch, light, min_value: 30.0, max_value: 90.0)}
    end

    test "shows the chart with history and range status", %{
      conn: conn,
      batch: batch,
      batch_sensor: batch_sensor
    } do
      {:ok, view, _html} = live(conn, ~p"/recipe-batch/#{batch.id}")
      chart = "#chart-wrapper-sensor-chart-#{batch_sensor.id}"

      assert has_element?(view, "#{chart} [phx-hook=ChartHook][data-min='30.0'][data-max='90.0']")
      assert has_element?(view, "#{chart} [id^=chart-status-]", "In range")
      assert has_element?(view, "#chart-table-sensor-chart-#{batch_sensor.id} tbody tr", "60.00")
    end

    test "live readings go to the active chart and update the status", %{
      conn: conn,
      batch: batch,
      batch_sensor: batch_sensor,
      light: light
    } do
      {:ok, view, _html} = live(conn, ~p"/recipe-batch/#{batch.id}")
      chart_id = "sensor-chart-#{batch_sensor.id}"

      send(view.pid, {:new_reading, reading(light, 95.5)})

      assert_push_event(view, "new-data", %{chart_id: ^chart_id, value: 95.5})
      assert has_element?(view, "#chart-wrapper-#{chart_id} [id^=chart-status-]", "Out of range")
    end

    test "detach stops the chart, and a re-attached sensor gets its own live chart", %{
      conn: conn,
      batch: batch,
      batch_sensor: old,
      node: node,
      light: light
    } do
      {:ok, view, _html} = live(conn, ~p"/recipe-batch/#{batch.id}")

      view |> element("#detach-node-#{node.id}") |> render_click()
      assert has_element?(view, "#chart-wrapper-sensor-chart-#{old.id}", "Stopped")

      # Attach the same sensor again: two charts for one sensor, distinct ids
      new = batch_sensor_fixture(batch, light)
      {:ok, view, _html} = live(conn, ~p"/recipe-batch/#{batch.id}")
      assert has_element?(view, "#chart-wrapper-sensor-chart-#{old.id}")
      assert has_element?(view, "#chart-wrapper-sensor-chart-#{new.id}")

      send(view.pid, {:new_reading, reading(light, 70.0)})

      new_chart = "sensor-chart-#{new.id}"
      assert_push_event(view, "new-data", %{chart_id: ^new_chart})
      old_chart = "sensor-chart-#{old.id}"
      refute_push_event(view, "new-data", %{chart_id: ^old_chart})
    end
  end
end
