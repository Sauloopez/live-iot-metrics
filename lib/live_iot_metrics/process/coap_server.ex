defmodule LiveMetrics.CoapServer do
  alias LiveMetrics.Sync.CoapResources
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

    # Nodes that store measurements and synchronize when they have a network
    :coap_server_registry.add_handler(["sync"], __MODULE__, nil)
    :coap_server_registry.add_handler(["status"], __MODULE__, nil)
    :coap_server_registry.add_handler(["sensors"], __MODULE__, nil)

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

  def coap_post(
        _ch_id,
        [resource],
        _name,
        {:coap_content, _t, _max_age, content_type, _p, payload}
      ) do
    Logger.info("Received request")

    result =
      case resource do
        "status" ->
          CoapResources.status(payload)

        "sync" ->
          CoapResources.sync(payload)

        "sensors" ->
          CoapResources.sensors(payload)

        "metrics" ->
          case content_type do
            "application/json" -> CoapResources.metrics(payload)
            _ -> {:coap_error, :bad_request}
          end

        _ ->
          {:coap_error, :not_found}
      end

    case result do
      :ok -> {:ok, :created, {:coap_content, :undefined, 0, :undefined, [], "OK"}}
      {:ok, body} -> {:ok, :created, {:coap_content, :undefined, 0, :undefined, [], body}}
      {:error, reason} -> reject(resource, reason)
      {:coap_error, error} -> {:error, error}
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

  defp reject(resource, reason) do
    Logger.warning("CoAP /#{resource} rejected: #{reason}")
    {:error, :bad_request}
  end
end
