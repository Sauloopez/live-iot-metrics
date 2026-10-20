defmodule LiveMetrics.Models.SensorTest do
  use LiveMetrics.DataCase, async: true

  import LiveMetrics.Fixtures
  alias LiveMetrics.Models.Sensor

  test "update_or_create/4 reuses the sensor with the same node sensor id" do
    node = node_fixture()

    {:ok, created} = Sensor.update_or_create(node, 1, "temperature", 0.5)
    {:ok, updated} = Sensor.update_or_create(node, 1, "air_temperature", 1.0)

    assert created.id == updated.id
    assert updated.sensor_type == "air_temperature"
    assert updated.precision == 1.0
  end

  test "deactivate/1 and activate/1 toggle recording" do
    sensor = sensor_fixture(node_fixture())

    {:ok, inactive} = Sensor.deactivate(sensor)
    refute inactive.active
    assert inactive.inactivated_at

    {:ok, active} = Sensor.activate(inactive)
    assert active.active
    assert is_nil(active.inactivated_at)
  end

  test "distinct_types/0 lists each reported type once, sorted" do
    node = node_fixture()
    sensor_fixture(node, node_sensor_id: 1, sensor_type: "light")
    sensor_fixture(node, node_sensor_id: 2, sensor_type: "air_humidity")
    sensor_fixture(node_fixture(), node_sensor_id: 1, sensor_type: "light")

    assert Sensor.distinct_types() == ["air_humidity", "light"]
  end
end
