defmodule LiveMetrics.Coap.Server do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Application.ensure_all_started(:gen_coap)

    # Start the UDP server on the default CoAP port (5683)
    :coap_server.start_udp(:live_metrics_coap_udp, 5683)

    # Register endpoints
    :coap_server_registry.add_handler(["grettings"], __MODULE__, nil)
    :coap_server_registry.add_handler(["metrics"], __MODULE__, nil)

    Logger.info("CoAP server started and endpoints registered.")

    {:ok, %{}}
  end

  def coap_discover(prefix, _args) do
    [{:absolute, prefix, []}]
  end

  def coap_get(_ch_id, ["grettings"], _name, _query, _content) do
    {:coap_content, :undefined, 60, :undefined, "Hello from CoAP!"}
  end

  def coap_get(_ch_id, _prefix, _name, _query, _content) do
    {:error, :not_found}
  end

  def coap_post(_ch_id, ["metrics"], _name, {:coap_content, _etag, _max_age, _format, payload}) do
    case Jason.decode(payload) do
      {:ok, data} ->
        case handle_metrics(data) do
          :ok ->
            {:ok, :created, {:coap_content, :undefined, 60, :undefined, "OK"}}

          :error ->
            {:error, :internal_server_error}
        end

      {:error, _} ->
        {:error, :bad_request}
    end
  end

  def coap_post(_ch_id, _prefix, _name, _content) do
    {:error, :method_not_allowed}
  end

  def coap_put(_ch_id, _prefix, _name, _content) do
    {:error, :method_not_allowed}
  end

  def coap_delete(_ch_id, _prefix, _name) do
    {:error, :method_not_allowed}
  end

  def coap_observe(_ch_id, _prefix, _name, _ack, _content) do
    {:error, :not_implemented}
  end

  def coap_unobserve(_state) do
    :ok
  end

  def coap_ack(_ref, state) do
    {:ok, state}
  end

  # --- Internal functions ---

  defp handle_metrics(data) do
    mac = Map.get(data, "mac_address")
    sensor_id = Map.get(data, "sensor_id")
    raw_value = Map.get(data, "value")

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

    sensor_precision = Map.get(data, "precision")

    precision =
      cond do
        is_bitstring(sensor_precision) ->
          case Float.parse(sensor_precision) do
            {f, _} -> f
            :error -> 0.0
          end

        is_float(sensor_precision) ->
          sensor_precision
      end

    reading_time = Map.get(data, "reading_time")
    sensor_type = String.downcase(Map.get(data, "sensor_type"))

    with {:ok, node} <- LiveMetrics.Nodes.get_or_insert(mac),
         {:ok, sensor} <-
           LiveMetrics.Sensor.update_or_create(node, sensor_id, sensor_type, precision),
         {:ok, _reading} <-
           LiveMetrics.SensorReading.create_reading(%{
             sensor_id: sensor.id,
             value: value,
             reading_time: reading_time
           }) do
      :ok
    else
      err ->
        Logger.error("Failed to process metrics: #{inspect(err)}")
        :error
    end
  end
end
