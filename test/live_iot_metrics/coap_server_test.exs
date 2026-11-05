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

  describe "nodes with local storage" do
    alias LiveMetrics.Health.NodeStatusReport
    alias LiveMetrics.Sync.{DataFrame, Ingest}

    @mac_bytes <<0x02, 0x00, 0x00, 0x00, 0xC0, 0x01>>
    @mac "02:00:00:00:C0:01"

    defp record(seq, sensor_id, value),
      do:
        <<0x84, 0x1A, seq::32, 0x1A, 1_762_164_450 + seq * 60::32, sensor_id, 0xFA,
          value::float-32>>

    defp sync_payload(seqs, sensor_id \\ 1) do
      records = Enum.map_join(seqs, &record(&1, sensor_id, &1 * 1.0))
      @mac_bytes <> DataFrame.build(0, Enum.min(seqs), Enum.count(seqs), records)
    end

    test "POST /sync stores the frame and answers the watermark and the server time" do
      assert {:ok, :created, {:coap_content, _, _, _, _, <<acked::little-32, time::little-32>>}} =
               CoapServer.coap_post(
                 @ch_id,
                 ["sync"],
                 nil,
                 content(sync_payload(1..5), :undefined)
               )

      assert acked == 5
      assert abs(time - System.os_time(:second)) < 5
      assert Ingest.acked_seq(@mac) == 5

      # A resend is confirmed again without storing twice
      assert {:ok, :created, {:coap_content, _, _, _, _, <<5::little-32, _::32>>}} =
               CoapServer.coap_post(
                 @ch_id,
                 ["sync"],
                 nil,
                 content(sync_payload(3..5), :undefined)
               )
    end

    test "POST /sync rejects a damaged frame" do
      <<head::binary-size(20), byte, rest::binary>> = sync_payload(1..3)
      damaged = <<head::binary, Bitwise.bxor(byte, 0xFF), rest::binary>>

      assert CoapServer.coap_post(@ch_id, ["sync"], nil, content(damaged, :undefined)) ==
               {:error, :bad_request}

      assert Ingest.acked_seq(@mac) == 0
    end

    test "POST /sensors types the measurements sent afterwards" do
      sensors =
        Jason.encode!(%{
          "mc" => @mac,
          "d" => [%{"i" => 7, "t" => "Water_Temperature", "pr" => 1}]
        })

      assert {:ok, :created, _} = CoapServer.coap_post(@ch_id, ["sensors"], nil, content(sensors))

      {:ok, :created, _} =
        CoapServer.coap_post(@ch_id, ["sync"], nil, content(sync_payload(1..2, 7), :undefined))

      node = Repo.get_by!(Nodes, mac: @mac)

      assert Repo.get_by!(Sensor, node_id: node.id, node_sensor_id: 7).sensor_type ==
               "water_temperature"
    end

    test "POST /status stores a health report sent over CoAP" do
      status =
        Jason.encode!(%{
          "mc" => @mac,
          "v" => "coap",
          "b" => %{"mv" => 3900, "p" => 68},
          "st" => %{"pd" => 12}
        })

      assert {:ok, :created, _} = CoapServer.coap_post(@ch_id, ["status"], nil, content(status))

      assert [%{transport: "coap", battery_percent: 68, pending: 12}] =
               NodeStatusReport.recent(@mac)
    end

    test "invalid status or sensor lists are rejected" do
      assert CoapServer.coap_post(@ch_id, ["status"], nil, content("{}")) ==
               {:error, :bad_request}

      assert CoapServer.coap_post(@ch_id, ["sensors"], nil, content("nope")) ==
               {:error, :bad_request}
    end
  end
end
