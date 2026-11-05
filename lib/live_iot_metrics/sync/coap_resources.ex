defmodule LiveMetrics.Sync.CoapResources do
  @moduledoc """
  CoAP resources of nodes that store their measurements and synchronize when they have a
  network (docs/tundra/PLAN.md, section 6.2). Same protocol as the USB extraction.

    * `POST /sync`    `MAC (6 bytes) · DATA frame` →
                      `acked_seq u32 · server_time u32` (little endian). The node releases
                      everything up to `acked_seq` and corrects its clock.
    * `POST /status`  JSON `{"mc": MAC, "v": variant, ...status keys}` (the serial `status`
                      response plus the node identity) → health report, transport `coap`
    * `POST /sensors` JSON `{"mc": MAC, "d": [sensor list items]}` → registers the node's
                      sensors so its measurements get the right type
  """
  alias LiveMetrics.MetricsBuffer
  alias LiveMetrics.Health.NodeStatusReport
  alias LiveMetrics.Models.{Nodes, Sensor}
  alias LiveMetrics.Sync.{DataFrame, Ingest}

  @spec sync(binary()) :: {:ok, binary()} | {:error, String.t()}
  def sync(<<mac_bytes::binary-size(6), frame::binary>>) do
    with {:ok, %{records: records}} <- DataFrame.parse(frame),
         {:ok, result} <- Ingest.ingest(format_mac(mac_bytes), records) do
      {:ok, <<result.acked_seq::little-32, System.os_time(:second)::little-32>>}
    else
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  def sync(_payload), do: {:error, "payload too short"}

  @spec status(binary()) :: :ok | {:error, String.t()}
  def status(payload) do
    with {:ok, %{"mc" => mac} = status} when is_binary(mac) <- Jason.decode(payload),
         {:ok, _report} <- NodeStatusReport.record(mac, status["v"], "coap", status) do
      :ok
    else
      _ -> {:error, "invalid status"}
    end
  end

  @spec sensors(binary()) :: :ok | {:error, String.t()}
  def sensors(payload) do
    with {:ok, %{"mc" => mac, "d" => sensors}} when is_binary(mac) and is_list(sensors) <-
           Jason.decode(payload),
         {:ok, node} <- Nodes.ensure(mac) do
      Enum.each(sensors, fn
        %{"i" => id, "t" => type} = s when is_integer(id) and is_binary(type) ->
          Sensor.update_or_create(node, id, String.downcase(type), (s["pr"] || 1) * 1.0)

        _invalid ->
          :skip
      end)
    else
      _ -> {:error, "invalid sensor list"}
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

  defp format_mac(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.map_join(":", &(&1 |> Integer.to_string(16) |> String.pad_leading(2, "0")))
  end
end
