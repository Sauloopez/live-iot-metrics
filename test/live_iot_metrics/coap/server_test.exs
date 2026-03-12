defmodule LiveMetrics.Coap.ServerTest do
  use LiveMetrics.DataCase

  alias LiveMetrics.Coap.Server

  describe "coap server" do
    test "discover returns available endpoints" do
      expected = [{:absolute, ["prefix"], []}]
      assert Server.coap_discover(["prefix"], nil) == expected
    end

    test "GET /grettings returns hello message" do
      ch_id = {{127, 0, 0, 1}, 5683}
      expected = {:coap_content, :undefined, 60, :undefined, "Hello from CoAP!"}
      assert Server.coap_get(ch_id, ["grettings"], nil, nil, nil) == expected
    end

    test "GET /unknown returns not_found" do
      ch_id = {{127, 0, 0, 1}, 5683}
      assert Server.coap_get(ch_id, ["unknown"], nil, nil, nil) == {:error, :not_found}
    end

    test "POST /metrics creates new readings" do
      ch_id = {{127, 0, 0, 1}, 5683}

      payload =
        Jason.encode!(%{
          "mac_address" => "00:1A:2B:3C:4D:5E",
          "sensor_id" => 1,
          "value" => 23.5,
          "reading_time" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

      content = {:coap_content, :undefined, 60, :undefined, payload}

      assert {:ok, :created, {:coap_content, :undefined, 60, :undefined, "OK"}} =
               Server.coap_post(ch_id, ["metrics"], nil, content)

      assert {:ok, node} = LiveMetrics.Nodes.get_or_insert("00:1A:2B:3C:4D:5E")

      # Should be able to see the reading
      sensor = LiveMetrics.Repo.get_by(LiveMetrics.Sensor, node_sensor_id: 1, node_id: node.id)
      assert sensor

      reading =
        LiveMetrics.Repo.get_by(LiveMetrics.SensorReading, sensor_id: sensor.id, value: 23.5)

      assert reading
    end

    test "POST /metrics handles invalid json" do
      ch_id = {{127, 0, 0, 1}, 5683}
      content = {:coap_content, :undefined, 60, :undefined, "{invalid}"}

      assert Server.coap_post(ch_id, ["metrics"], nil, content) == {:error, :bad_request}
    end

    test "POST /unknown returns method_not_allowed" do
      ch_id = {{127, 0, 0, 1}, 5683}
      content = {:coap_content, :undefined, 60, :undefined, "test"}

      assert Server.coap_post(ch_id, ["unknown"], nil, content) == {:error, :method_not_allowed}
    end

    test "PUT returns method_not_allowed" do
      assert Server.coap_put(nil, nil, nil, nil) == {:error, :method_not_allowed}
    end

    test "DELETE returns method_not_allowed" do
      assert Server.coap_delete(nil, nil, nil) == {:error, :method_not_allowed}
    end
  end
end
