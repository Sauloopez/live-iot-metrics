defmodule LiveMetrics.Sync.MeasurementCbor do
  @moduledoc """
  Decodes the measurements stored by the nodes (iot-node `MeasurementCodec.h`).

  Each measurement is a CBOR array of 4 items, records are concatenated with no separator:

      [seq :: uint, ts :: uint (Unix seconds, 0 = unknown), sensor_id :: uint, value :: float32]

  Only this fixed shape is accepted, so a general CBOR library is not needed.
  """

  @type measurement :: %{
          seq: non_neg_integer(),
          ts: non_neg_integer(),
          sensor_id: non_neg_integer(),
          value: float()
        }

  @doc "Decodes concatenated records. Returns `{:error, reason}` on the first invalid one."
  @spec decode_all(binary()) :: {:ok, [measurement()]} | {:error, String.t()}
  def decode_all(binary), do: decode_all(binary, [])

  defp decode_all(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_all(binary, acc) do
    case decode(binary) do
      {:ok, measurement, rest} -> decode_all(rest, [measurement | acc])
      {:error, _} = error -> error
    end
  end

  # 0x84 = array of 4 items
  defp decode(<<0x84, rest::binary>>) do
    with {:ok, seq, rest} <- uint(rest),
         {:ok, ts, rest} <- uint(rest),
         {:ok, sensor_id, rest} <- uint(rest),
         {:ok, value, rest} <- float32(rest) do
      {:ok, %{seq: seq, ts: ts, sensor_id: sensor_id, value: value}, rest}
    end
  end

  defp decode(_), do: {:error, "expected a 4 item array"}

  # CBOR major type 0 (unsigned integer)
  defp uint(<<value, rest::binary>>) when value < 24, do: {:ok, value, rest}
  defp uint(<<0x18, value::8, rest::binary>>), do: {:ok, value, rest}
  defp uint(<<0x19, value::16, rest::binary>>), do: {:ok, value, rest}
  defp uint(<<0x1A, value::32, rest::binary>>), do: {:ok, value, rest}
  defp uint(<<0x1B, value::64, rest::binary>>), do: {:ok, value, rest}
  defp uint(_), do: {:error, "expected an unsigned integer"}

  # 0xFA = single precision float. NaN and infinity do not match the float pattern.
  defp float32(<<0xFA, value::float-32, rest::binary>>), do: {:ok, value, rest}
  defp float32(_), do: {:error, "expected a float32 value"}
end
