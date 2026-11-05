defmodule LiveMetrics.Sync.DataFrameTest do
  use ExUnit.Case, async: true

  alias LiveMetrics.Sync.{DataFrame, MeasurementCbor}

  # First frame built by the firmware's SyncStream for 3 stored measurements:
  #   {1, 1762164450, 1, 21.5}, {2, 1762164510, 2, -3.25}, {3, 1762164570, 300, 1000.0}
  @firmware_frame Base.decode16!(
                    "010000010000000384011A69087EE201FA41AC000084021A69087F1E02FAC050000084031A69087F5A19012CFA447A000089D6"
                  )

  test "parses a frame built by the firmware" do
    assert {:ok, %{frame_no: 0, first_seq: 1, count: 3, records: records}} =
             DataFrame.parse(@firmware_frame)

    assert {:ok, [%{seq: 1, value: 21.5}, %{seq: 2, value: -3.25}, %{seq: 3, sensor_id: 300}]} =
             MeasurementCbor.decode_all(records)
  end

  test "CRC-16/CCITT-FALSE check value" do
    assert DataFrame.crc16("123456789") == 0x29B1
  end

  test "build/4 produces what parse/1 reads" do
    frame = DataFrame.build(7, 1001, 2, <<1, 2, 3>>)

    assert {:ok, %{frame_no: 7, first_seq: 1001, count: 2, records: <<1, 2, 3>>}} =
             DataFrame.parse(frame)
  end

  test "rejects damaged, short or foreign frames" do
    <<head::binary-size(10), byte, rest::binary>> = @firmware_frame
    damaged = <<head::binary, Bitwise.bxor(byte, 0x10), rest::binary>>

    assert DataFrame.parse(damaged) == {:error, "bad CRC"}
    assert DataFrame.parse(<<1, 2, 3>>) == {:error, "frame too short"}

    foreign = <<0x02, 0::little-16, 1::little-32, 0>>

    assert DataFrame.parse(<<foreign::binary, DataFrame.crc16(foreign)::little-16>>) ==
             {:error, "unknown frame type"}
  end
end
