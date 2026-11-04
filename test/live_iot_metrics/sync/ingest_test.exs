defmodule LiveMetrics.Sync.IngestTest do
  # Not async: inserting readings creates TimescaleDB chunks inside the sandbox transaction,
  # and concurrent chunk creation deadlocks
  use LiveMetrics.DataCase, async: false

  import LiveMetrics.Fixtures

  alias LiveMetrics.Models.{NodeSensorConfig, Nodes, Sensor, SensorReading}
  alias LiveMetrics.Sync.Ingest

  @t0 1_762_164_450

  # Same encoding as the firmware (see MeasurementCborTest for a vector made by the firmware)
  defp record(seq, sensor_id, value, ts \\ nil) do
    <<0x84>> <>
      uint(seq) <> uint(ts || @t0 + seq * 60) <> uint(sensor_id) <> <<0xFA, value::float-32>>
  end

  defp uint(v) when v < 24, do: <<v>>
  defp uint(v) when v < 256, do: <<0x18, v>>
  defp uint(v) when v < 65_536, do: <<0x19, v::16>>
  defp uint(v), do: <<0x1A, v::32>>

  defp records(seqs, sensor_id \\ 1), do: Enum.map_join(seqs, &record(&1, sensor_id, &1 * 1.5))

  defp stored_values(mac) do
    from(r in SensorReading,
      join: s in Sensor,
      on: s.id == r.sensor_id,
      join: n in Nodes,
      on: n.id == s.node_id,
      where: n.mac == ^mac,
      order_by: r.reading_time,
      select: {s.sensor_type, r.value, r.reading_time}
    )
    |> Repo.all()
  end

  setup do
    %{mac: unique_mac(), sensors: %{1 => %{type: "temperature", precision: 1.0}}}
  end

  test "stores measurements with the node's own time and confirms them", %{
    mac: mac,
    sensors: sensors
  } do
    assert {:ok, %{acked_seq: 3, stored: 3, ignored: 0}} =
             Ingest.ingest(mac, records(1..3), sensors)

    assert [{"temperature", 1.5, first_time} | _] = stored_values(mac)
    assert DateTime.to_unix(first_time) == @t0 + 60
    assert Ingest.acked_seq(mac) == 3
  end

  test "resends and a second extraction of the same storage are not duplicated", %{
    mac: mac,
    sensors: sensors
  } do
    {:ok, _} = Ingest.ingest(mac, records(1..5), sensors)

    assert {:ok, %{acked_seq: 7, stored: 2, ignored: 5}} =
             Ingest.ingest(mac, records(1..7), sensors)

    assert length(stored_values(mac)) == 7
  end

  test "a gap stops the watermark until the missing measurements arrive", %{
    mac: mac,
    sensors: sensors
  } do
    # 4 and 5 were lost (e.g. a frame with a bad CRC)
    assert {:ok, %{acked_seq: 3, stored: 3, ignored: 2}} =
             Ingest.ingest(mac, records([1, 2, 3, 6, 7]), sensors)

    # The node resends from acked_seq + 1
    assert {:ok, %{acked_seq: 7, stored: 4}} = Ingest.ingest(mac, records(4..7), sensors)
    assert length(stored_values(mac)) == 7
  end

  test "measurements without a valid time are skipped but still confirmed", %{
    mac: mac,
    sensors: sensors
  } do
    binary = record(1, 1, 10.0) <> record(2, 1, 20.0, 0) <> record(3, 1, 30.0)

    assert {:ok, %{acked_seq: 3, stored: 2, skipped_without_time: 1}} =
             Ingest.ingest(mac, binary, sensors)

    assert Enum.map(stored_values(mac), &elem(&1, 1)) == [10.0, 30.0]
  end

  test "sensor types fall back to the saved configuration when the node no longer has them", %{
    mac: mac
  } do
    {:ok, config} =
      NodeSensorConfig.create(mac, %{
        "pin" => "32",
        "sensor_type" => "soil_moisture",
        "driver" => "analog",
        "precision" => "1.0",
        "offset" => "0",
        "interval_ms" => "10000"
      })

    {:ok, _} = Ingest.ingest(mac, records(1..2, config.id), %{})

    assert [{"soil_moisture", _, _}, _] = stored_values(mac)
  end

  test "records of an unknown sensor are kept under a generic type", %{mac: mac} do
    {:ok, _} = Ingest.ingest(mac, records(1..1, 42), %{})
    assert [{"sensor_42", _, _}] = stored_values(mac)
  end

  test "invalid data stores nothing and keeps the watermark", %{mac: mac, sensors: sensors} do
    assert {:error, _} = Ingest.ingest(mac, records(1..2) <> <<0x84, 0x01>>, sensors)
    assert Ingest.acked_seq(mac) == 0
    assert stored_values(mac) == []
  end

  test "the MAC is matched regardless of case", %{sensors: sensors} do
    {:ok, _} = Ingest.ingest("aa:bb:cc:00:00:01", records(1..2), sensors)
    assert Ingest.acked_seq("AA:BB:CC:00:00:01") == 2
  end
end
