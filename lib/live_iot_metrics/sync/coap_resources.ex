defmodule LiveMetrics.Sync.CoapResources do
  @moduledoc """
  CoAP resources of nodes that store their measurements and synchronize when they have a
  network. Same protocol as the USB extraction.

  Every request is only validated here and queued in its buffer; the database work happens in
  the background and in batches, so the node gets its answer right away.

    * `POST /sync`    `MAC (6 bytes) · DATA frame` → `acked_seq u32 · server_time u32`
                      (little endian). `acked_seq` is the last **processed** watermark: the
                      frame just sent is confirmed in a later exchange. A frame with no
                      records only asks for the watermark. Queued in `LiveMetrics.SyncBuffer`.
    * `POST /status`  JSON `{"mc": MAC, "v": variant, ...status keys}` (the serial `status`
                      response plus the node identity) → health report, transport `coap`.
                      Queued in `LiveMetrics.StatusBuffer`.
    * `POST /sensors` JSON `{"mc": MAC, "d": [sensor list items]}` → registers the node's
                      sensors so its measurements get the right type. Queued in
                      `LiveMetrics.SensorsBuffer`.
  """
  alias LiveMetrics.{MetricsBuffer, SensorsBuffer, StatusBuffer, SyncBuffer}
  alias LiveMetrics.Sync.DataFrame

  @spec sync(binary()) :: {:ok, binary()} | {:error, String.t()}
  def sync(<<mac_bytes::binary-size(6), frame::binary>>) do
    with {:ok, %{first_seq: first_seq, records: records}} <- DataFrame.parse(frame) do
      mac = format_mac(mac_bytes)
      if records != <<>>, do: SyncBuffer.push(mac, first_seq, records)
      {:ok, <<SyncBuffer.watermark(mac)::little-32, System.os_time(:second)::little-32>>}
    end
  end

  def sync(_payload), do: {:error, "payload too short"}

  @spec status(binary()) :: :ok | {:error, String.t()}
  def status(payload) do
    case Jason.decode(payload) do
      {:ok, %{"mc" => mac} = status} when is_binary(mac) ->
        StatusBuffer.push(normalize_mac(mac), status)

      _ ->
        {:error, "invalid status"}
    end
  end

  @spec sensors(binary()) :: :ok | {:error, String.t()}
  def sensors(payload) do
    case Jason.decode(payload) do
      {:ok, %{"mc" => mac, "d" => sensors}} when is_binary(mac) and is_list(sensors) ->
        SensorsBuffer.push(normalize_mac(mac), sensors)

      _ ->
        {:error, "invalid sensor list"}
    end
  end

  @spec metrics(binary()) :: :ok | {:error, String.t()}
  def metrics(payload) do
    case Jason.decode(payload) do
      {:ok, data} -> handle_metrics(data)
      {:error, _} -> {:error, "Invalid format"}
    end
  end

  defp handle_metrics(data) do
    mac = Map.get(data, "m")
    raw_sensor_id = Map.get(data, "s")

    sensor_id =
      cond do
        is_integer(raw_sensor_id) -> raw_sensor_id
        is_bitstring(raw_sensor_id) -> String.length(raw_sensor_id)
        true -> 0
      end

    raw_value = Map.get(data, "v")

    value =
      cond do
        is_integer(raw_value) ->
          raw_value * 1.0

        is_float(raw_value) ->
          raw_value

        is_binary(raw_value) ->
          case Float.parse(raw_value) do
            {f, _} -> f
            :error -> 0.0
          end

        true ->
          0.0
      end

    sensor_precision = Map.get(data, "p")

    precision =
      cond do
        is_bitstring(sensor_precision) ->
          case Float.parse(sensor_precision) do
            {f, _} -> f
            :error -> 0.0
          end

        is_float(sensor_precision) ->
          sensor_precision

        # ArduinoJson serializes whole floats such as 1.0 as the integer 1
        is_integer(sensor_precision) ->
          sensor_precision * 1.0

        true ->
          0.0
      end

    sensor_type = String.downcase(Map.get(data, "t") || "unknown", :default)
    MetricsBuffer.enqueue(mac, sensor_id, sensor_type, precision, value, DateTime.utc_now())
    :ok
  end

  defp normalize_mac(mac), do: mac |> String.trim() |> String.upcase()

  defp format_mac(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.map_join(":", &(&1 |> Integer.to_string(16) |> String.pad_leading(2, "0")))
  end
end
