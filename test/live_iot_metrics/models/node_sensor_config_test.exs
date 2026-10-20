defmodule LiveMetrics.Models.NodeSensorConfigTest do
  use LiveMetrics.DataCase, async: true

  alias LiveMetrics.Models.NodeSensorConfig

  @mac "B4:BF:E9:04:E6:C4"
  @valid %{
    "pin" => "32",
    "sensor_type" => " Soil_Moisture ",
    "driver" => "analog",
    "precision" => "-0.058824",
    "offset" => "176.47",
    "interval_ms" => "30000"
  }

  test "create/2 assigns an integer id and normalizes the type" do
    assert {:ok, config} = NodeSensorConfig.create(@mac, @valid)
    assert is_integer(config.id)
    assert config.mac == @mac
    assert config.sensor_type == "soil_moisture"
  end

  test "mac is never cast from params" do
    {:ok, config} = NodeSensorConfig.create(@mac, Map.put(@valid, "mac", "00:00:00:00:00:00"))
    assert config.mac == @mac
  end

  test "rejects unknown drivers, invalid types, pins and short intervals" do
    {:error, changeset} =
      NodeSensorConfig.create(@mac, %{
        @valid
        | "driver" => "dht11",
          "sensor_type" => "bad,type",
          "pin" => "40",
          "interval_ms" => "100"
      })

    errors = errors_on(changeset)
    assert errors.driver
    assert errors.sensor_type
    assert errors.pin
    assert errors.interval_ms
  end

  test "the same pin and driver can not be used twice on a node" do
    {:ok, _} = NodeSensorConfig.create(@mac, @valid)
    assert {:error, changeset} = NodeSensorConfig.create(@mac, @valid)

    assert "this node already has a sensor with this driver on this pin" in errors_on(changeset).pin

    assert {:ok, _} = NodeSensorConfig.create("AA:AA:AA:AA:AA:AA", @valid)
  end

  test "delete_all_by_mac/1 only deletes the given node" do
    {:ok, _} = NodeSensorConfig.create(@mac, @valid)
    {:ok, _} = NodeSensorConfig.create(@mac, %{@valid | "pin" => "33"})
    {:ok, other} = NodeSensorConfig.create("AA:AA:AA:AA:AA:AA", @valid)

    assert NodeSensorConfig.delete_all_by_mac(@mac) == 2
    assert NodeSensorConfig.list_by_mac(@mac) == []
    assert [%{id: id}] = NodeSensorConfig.list_by_mac("AA:AA:AA:AA:AA:AA")
    assert id == other.id
  end

  test "to_serial_command/2 builds the firmware payload" do
    {:ok, config} = NodeSensorConfig.create(@mac, @valid)

    assert %{command: "sensor", data: data} = NodeSensorConfig.to_serial_command(config, "add")
    assert data.action == "add"
    assert data.id == config.id
    assert data.type == "soil_moisture"
    assert data.interval == 30_000
  end

  describe "sync_status/2" do
    setup do
      {:ok, config} = NodeSensorConfig.create(@mac, @valid)

      node_sensor = %{
        "id" => config.id,
        "pin" => 32,
        "type" => "soil_moisture",
        "driver" => "analog",
        # Floats come back through ArduinoJson with limited precision
        "precision" => -0.058824002,
        "offset" => 176.47,
        "interval" => 30_000
      }

      %{config: config, node_sensor: node_sensor}
    end

    test "synced when the node has the same values", %{config: config, node_sensor: node_sensor} do
      assert NodeSensorConfig.sync_status(config, node_sensor) == :synced
    end

    test "differs when a value changed on the node", %{config: config, node_sensor: node_sensor} do
      assert NodeSensorConfig.sync_status(config, %{node_sensor | "pin" => 33}) == :differs
    end

    test "missing when the node does not have it", %{config: config} do
      assert NodeSensorConfig.sync_status(config, nil) == :missing
    end
  end
end
