defmodule LiveMetrics.Metrics.ProcessorTest do
  @moduledoc "Covers the insert_reading_in_batch/1 database function used for every CoAP batch."
  use LiveMetrics.DataCase, async: true

  import LiveMetrics.Fixtures
  alias LiveMetrics.Metrics.Processor
  alias LiveMetrics.Models.{Nodes, Sensor, SensorReading}

  defp metric(mac, sensor_id, type, value, attrs \\ %{}) do
    Map.merge(
      %{
        mac: mac,
        sensor_id: sensor_id,
        sensor_type: type,
        precision: 1.0,
        value: value,
        reading_time: DateTime.utc_now()
      },
      attrs
    )
  end

  defp readings_for(mac, node_sensor_id) do
    from(r in SensorReading,
      join: s in Sensor,
      on: s.id == r.sensor_id,
      join: n in Nodes,
      on: n.id == s.node_id,
      where: n.mac == ^mac and s.node_sensor_id == ^node_sensor_id,
      order_by: r.reading_time,
      select: r.value
    )
    |> Repo.all()
  end

  test "creates the node and its sensors on the first reading" do
    mac = unique_mac()
    Processor.process_batch([metric(mac, 1, "light", 60.0), metric(mac, 2, "soil_moisture", 40)])

    node = Repo.get_by!(Nodes, mac: mac)
    assert node.name == mac

    assert Repo.get_by!(Sensor, node_id: node.id, node_sensor_id: 2).sensor_type ==
             "soil_moisture"

    assert readings_for(mac, 1) == [60.0]
    assert readings_for(mac, 2) == [40.0]
  end

  test "keeps storing readings for nodes that already exist" do
    node = node_fixture(name: "Greenhouse node")
    Processor.process_batch([metric(node.mac, 1, "light", 1.0)])
    Processor.process_batch([metric(node.mac, 1, "light", 2.0)])

    assert readings_for(node.mac, 1) == [1.0, 2.0]
    # The user-given name is not overwritten
    assert Repo.get!(Nodes, node.id).name == "Greenhouse node"
  end

  test "stores several readings of the same sensor in one batch" do
    mac = unique_mac()
    now = DateTime.utc_now()

    Processor.process_batch([
      metric(mac, 1, "light", 1.0, %{reading_time: DateTime.add(now, -2)}),
      metric(mac, 1, "light", 2.0, %{reading_time: DateTime.add(now, -1)}),
      metric(mac, 1, "light", 3.0, %{reading_time: now})
    ])

    assert readings_for(mac, 1) == [1.0, 2.0, 3.0]
  end

  test "readings of one node do not land on another node's sensor with the same id" do
    a = unique_mac()
    b = unique_mac()
    Processor.process_batch([metric(a, 1, "light", 10.0), metric(b, 1, "light", 20.0)])

    assert readings_for(a, 1) == [10.0]
    assert readings_for(b, 1) == [20.0]
  end

  test "skips readings from inactive sensors" do
    node = node_fixture()
    {:ok, _} = node |> sensor_fixture(sensor_type: "light") |> Sensor.deactivate()

    Processor.process_batch([metric(node.mac, 1, "light", 99.0)])

    assert readings_for(node.mac, 1) == []
  end

  test "updates the sensor type and precision reported by the node" do
    node = node_fixture()
    sensor_fixture(node, sensor_type: "light", precision: 1.0)

    Processor.process_batch([
      metric(node.mac, 1, "soil_moisture", 50.0, %{precision: 0.5})
    ])

    sensor = Repo.get_by!(Sensor, node_id: node.id, node_sensor_id: 1)
    assert {sensor.sensor_type, sensor.precision} == {"soil_moisture", 0.5}
  end
end
