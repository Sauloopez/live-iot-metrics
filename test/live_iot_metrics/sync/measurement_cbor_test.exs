defmodule LiveMetrics.Sync.MeasurementCborTest do
  use ExUnit.Case, async: true

  alias LiveMetrics.Sync.MeasurementCbor

  # Produced by the firmware's MeasurementCodec::encode (iot-node), so the server stays in
  # step with what the nodes write:
  #   {1, 1762164450, 3, 21.5}, {4000000000, 1762164510, 300, -12.75}, {2, 0, 0, 0.0}
  @firmware_vector Base.decode16!(
                     "84011A69087EE203FA41AC0000841AEE6B28001A69087F1E19012CFAC14C000084020000FA00000000"
                   )

  test "decodes records written by the firmware" do
    assert {:ok,
            [
              %{seq: 1, ts: 1_762_164_450, sensor_id: 3, value: 21.5},
              %{seq: 4_000_000_000, ts: 1_762_164_510, sensor_id: 300, value: -12.75},
              %{seq: 2, ts: 0, sensor_id: 0, value: +0.0}
            ]} = MeasurementCbor.decode_all(@firmware_vector)
  end

  test "an empty binary has no records" do
    assert MeasurementCbor.decode_all(<<>>) == {:ok, []}
  end

  test "rejects truncated or foreign data" do
    truncated = binary_part(@firmware_vector, 0, byte_size(@firmware_vector) - 2)
    assert {:error, _} = MeasurementCbor.decode_all(truncated)
    assert {:error, _} = MeasurementCbor.decode_all(<<0xA1, 0x01, 0x02>>)
    # NaN can not be a measurement
    assert {:error, _} = MeasurementCbor.decode_all(<<0x84, 1, 1, 1, 0xFA, 0x7F, 0xC0, 0, 0>>)
  end
end
