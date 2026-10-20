defmodule LiveMetrics.CoapServerTest do
  # Not async: the end-to-end test goes through the global MetricsBuffer, whose insert
  # task needs the shared sandbox connection
  use LiveMetrics.DataCase, async: false

  alias LiveMetrics.CoapServer
  alias LiveMetrics.Models.{Nodes, Sensor, SensorReading}

  @ch_id {{127, 0, 0, 1}, 5683}

  defp content(payload, format \\ "application/json"),
    do: {:coap_content, :undefined, 60, format, [], payload}

  test "discover returns the prefix as an endpoint" do
    assert CoapServer.coap_discover(["metrics"], nil) == [{:absolute, ["metrics"], []}]
  end

  test "GET /greetings answers hello" do
    assert {:coap_content, _, _, _, _, "Hello from CoAP!"} =
             CoapServer.coap_get(@ch_id, ["greetings"], nil, nil, nil)
  end

  test "GET on an unknown path is not found" do
    assert CoapServer.coap_get(@ch_id, ["unknown"], nil, nil, nil) == {:error, :not_found}
  end

  test "POST /metrics rejects invalid JSON and other content types" do
    assert CoapServer.coap_post(@ch_id, ["metrics"], nil, content("{invalid")) ==
             {:error, :bad_request}

    assert CoapServer.coap_post(@ch_id, ["metrics"], nil, content("{}", "text/plain")) ==
             {:error, :bad_request}
  end

  test "POST on an unknown path is not found" do
    assert CoapServer.coap_post(@ch_id, ["unknown"], nil, content("{}")) == {:error, :not_found}
  end

  test "PUT and DELETE are not allowed" do
    assert CoapServer.coap_put(@ch_id, ["metrics"], nil, nil) == {:error, :method_not_allowed}
    assert CoapServer.coap_delete(@ch_id, ["metrics"], nil) == {:error, :method_not_allowed}
  end

  describe "POST /metrics end to end" do
    setup do
      test_pid = self()
      handler_id = {__MODULE__, make_ref()}

      # Notifies the test when the buffer task has run the batch insert, so the test does
      # not have to sleep waiting for the flush
      :telemetry.attach(
        handler_id,
        [:live_metrics, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if query =~ "insert_reading_in_batch", do: send(test_pid, :batch_inserted)
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
    end

    test "stores the reading sent by a node (ESP32 payload format)" do
      mac = LiveMetrics.Fixtures.unique_mac()

      # ArduinoJson serializes 1.0 as the integer 1
      payload = Jason.encode!(%{"m" => mac, "s" => 1, "t" => "Light", "p" => 1, "v" => 1966.3})

      assert {:ok, :created, {:coap_content, _, _, _, _, "OK"}} =
               CoapServer.coap_post(@ch_id, ["metrics"], nil, content(payload))

      send(LiveMetrics.MetricsBuffer, :flush)
      assert_receive :batch_inserted, 2_000

      node = Repo.get_by!(Nodes, mac: mac)
      sensor = Repo.get_by!(Sensor, node_id: node.id, node_sensor_id: 1)
      assert sensor.sensor_type == "light"
      assert sensor.precision == 1.0

      assert [%{value: 1966.3}] =
               Repo.all(from r in SensorReading, where: r.sensor_id == ^sensor.id)
    end
  end
end
