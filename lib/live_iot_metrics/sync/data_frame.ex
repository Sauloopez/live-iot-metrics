defmodule LiveMetrics.Sync.DataFrame do
  @moduledoc """
  DATA frames sent by the nodes (iot-node `SyncStream.h`, docs/tundra/SERIAL_API.md).

  The same frame travels over USB (COBS encoded, decoded by the browser) and over CoAP
  (`POST /sync`, preceded by the node MAC). Little endian:

      type u8 (0x01) · frame_no u16 · first_seq u32 · count u8 · CBOR records · crc u16

  The CRC is CRC-16/CCITT-FALSE of every byte before it.
  """
  import Bitwise

  @type_data 0x01
  @header_size 8

  @type t :: %{
          frame_no: non_neg_integer(),
          first_seq: non_neg_integer(),
          count: non_neg_integer(),
          records: binary()
        }

  @spec parse(binary()) :: {:ok, t()} | {:error, String.t()}
  def parse(frame) when byte_size(frame) >= @header_size + 2 do
    body_size = byte_size(frame) - 2
    <<body::binary-size(body_size), crc::little-16>> = frame

    with :ok <- check_crc(body, crc),
         <<@type_data, frame_no::little-16, first_seq::little-32, count, records::binary>> <- body do
      {:ok, %{frame_no: frame_no, first_seq: first_seq, count: count, records: records}}
    else
      {:error, _} = error -> error
      _ -> {:error, "unknown frame type"}
    end
  end

  def parse(_frame), do: {:error, "frame too short"}

  @doc "Builds a DATA frame (used by tests and simulators)."
  @spec build(non_neg_integer(), non_neg_integer(), non_neg_integer(), binary()) :: binary()
  def build(frame_no, first_seq, count, records) do
    body = <<@type_data, frame_no::little-16, first_seq::little-32, count, records::binary>>
    <<body::binary, crc16(body)::little-16>>
  end

  @doc "CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF). `crc16(\"123456789\") == 0x29B1`."
  def crc16(data) do
    for <<byte <- data>>, reduce: 0xFFFF do
      crc ->
        Enum.reduce(1..8, bxor(crc, byte <<< 8), fn _, acc ->
          if (acc &&& 0x8000) != 0,
            do: bxor(acc <<< 1, 0x1021) &&& 0xFFFF,
            else: acc <<< 1 &&& 0xFFFF
        end)
    end
  end

  defp check_crc(body, crc) do
    if crc16(body) == crc, do: :ok, else: {:error, "bad CRC"}
  end
end
