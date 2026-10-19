defmodule LiveMetrics.CoapServer do
  alias LiveMetrics.MetricsBuffer
  use GenServer
  require Logger

  require Record

  Record.extract_all(from_lib: "gen_coap/include/coap.hrl")
  |> Enum.each(fn {name, definition} ->
    Record.defrecord(name, definition)
  end)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Application.ensure_all_started(:gen_coap)

    # Start the UDP server on the default CoAP port (5683)
    :coap_server.start_udp(:live_metrics_coap_udp, 5683)

    # Register endpoints
    :coap_server_registry.add_handler(["greetings"], __MODULE__, nil)
    :coap_server_registry.add_handler(["metrics"], __MODULE__, nil)

    Logger.info("CoAP server started and endpoints registered.")

    {:ok, %{}}
  end

  def coap_discover(prefix, _args) do
    [{:absolute, prefix, []}]
  end

  def coap_get(_ch_id, ["greetings"], _name, _query, _content) do
    # { :coap_content, etag, max_age, format, location_path, payload }
    {:coap_content, :undefined, 60, :undefined, [], "Hello from CoAP!"}
  end

  def coap_get(_ch_id, _prefix, _name, _query, _content) do
    {:error, :not_found}
  end

  def coap_post(_ch_id, p, _name, {:coap_content, _t, _max_age, content_type, _p, payload}) do
    # p expected ["metrics"]
    Logger.info("Received request")

    case p do
      ["metrics"] ->
        case content_type do
          "application/json" ->
            case Jason.decode(payload) do
              {:ok, data} ->
                case handle_metrics(data) do
                  :ok ->
                    {:ok, :created, {:coap_content, :undefined, 60, :undefined, [], "OK"}}
                end

              {:error, _} ->
                {:error, :bad_request}
            end

          _ ->
            {:error, :bad_request}
        end

      _ ->
        {:error, :not_found}
    end
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

        true ->
          0.0
      end

    sensor_type = String.downcase(Map.get(data, "t") || "unknown", :default)
    MetricsBuffer.enqueue(mac, sensor_id, sensor_type, precision, value, DateTime.utc_now())
    :ok
  end
end
