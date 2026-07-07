node_mac = "00:1A:2B:3C:4D:5E"
IO.puts("Simulating data for #{node_mac}")

# Simulating an API request for CoAP
LiveMetrics.Coap.Server.coap_post(
  {{127, 0, 0, 1}, 5683},
  ["metrics"],
  nil,
  {:coap_content, :undefined, 60, :undefined,
   Jason.encode!(%{
     "mac_address" => node_mac,
     "sensor_id" => 1,
     "sensor_type" => "temperature",
     "value" => :rand.uniform() * 100,
     "reading_time" => DateTime.utc_now() |> DateTime.to_iso8601()
   })}
)

IO.puts("Done")
